import Foundation
import OSLog
import PinesCore
import UIKit
import WebKit

private let browserRuntimeLogger = Logger(subsystem: "com.schtack.pines", category: "BrowserRuntime")

@MainActor
final class WKWebViewBrowserRuntime: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var navigationContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
    }

    func observeSpec() throws -> ToolSpec<BrowserObserveInput, BrowserObserveOutput> {
        try ToolSpec(
            name: "browser.observe",
            description: "Read a constrained accessibility snapshot from the isolated in-app browser.",
            inputSchema: ToolIOSchema(
                properties: ["url": .init(type: .string, description: "Visible page URL.")],
                required: ["url"]
            ),
            outputSchema: ToolIOSchema(
                properties: ["snapshot": .init(type: .string, description: "Sanitized page snapshot.")],
                required: ["snapshot"]
            ),
            permissions: [.browser, .network],
            sideEffect: .readsExternalData,
            networkPolicy: .userApproved,
            timeoutSeconds: 10,
            explanationRequired: true
        ) { input in
            return try await MainActor.run {
                Task { try await self.observe(input) }
            }.value
        }
    }

    func actionSpec() throws -> ToolSpec<BrowserActionInput, BrowserActionOutput> {
        try ToolSpec(
            name: "browser.action",
            description: "Run a user-approved action in the isolated in-app browser.",
            inputSchema: BuiltInToolSpecs.browserActionSpec().inputSchema,
            outputSchema: BuiltInToolSpecs.browserActionSpec().outputSchema,
            permissions: [.browser, .network],
            sideEffect: .readsExternalData,
            networkPolicy: .userApproved,
            timeoutSeconds: 10,
            explanationRequired: true
        ) { input in
            return try await MainActor.run {
                Task { try await self.perform(input) }
            }.value
        }
    }

    func observe(_ input: BrowserObserveInput) async throws -> BrowserObserveOutput {
        let webView = ensureWebView()
        if let url = URL(string: input.url), webView.url != url {
            try await navigate(to: url)
        }
        return BrowserObserveOutput(snapshot: try await snapshotText())
    }

    func perform(_ input: BrowserActionInput) async throws -> BrowserActionOutput {
        switch input.kind {
        case .observe:
            return BrowserActionOutput(summary: "Observed page.", snapshot: try await snapshotText())
        case .navigate:
            guard let value = input.url, let url = URL(string: value) else {
                throw AgentError.invalidToolArguments("browser.action navigate requires url.")
            }
            try await navigate(to: url)
            return BrowserActionOutput(summary: "Navigated to \(url.absoluteString).", snapshot: try await snapshotText())
        case .click:
            guard let selector = input.selector else {
                throw AgentError.invalidToolArguments("browser.action click requires selector.")
            }
            try await evaluateJavaScript("document.querySelector(\(Self.jsString(selector)))?.click();")
            return BrowserActionOutput(summary: "Clicked \(selector).", snapshot: try await snapshotText())
        case .typeText:
            guard let selector = input.selector, let text = input.text else {
                throw AgentError.invalidToolArguments("browser.action typeText requires selector and text.")
            }
            try await evaluateJavaScript(
                """
                (() => {
                  const el = document.querySelector(\(Self.jsString(selector)));
                  if (!el) return false;
                  el.focus();
                  el.value = \(Self.jsString(text));
                  el.dispatchEvent(new Event('input', { bubbles: true }));
                  el.dispatchEvent(new Event('change', { bubbles: true }));
                  return true;
                })();
                """
            )
            return BrowserActionOutput(summary: "Typed into \(selector).", snapshot: try await snapshotText())
        case .submit:
            guard let selector = input.selector else {
                throw AgentError.invalidToolArguments("browser.action submit requires selector.")
            }
            try await evaluateJavaScript("document.querySelector(\(Self.jsString(selector)))?.submit?.();")
            await waitForNavigation()
            return BrowserActionOutput(summary: "Submitted \(selector).", snapshot: try await snapshotText())
        case .screenshot:
            let configuration = WKSnapshotConfiguration()
            let image = try await takeSnapshot(configuration: configuration)
            #if canImport(UIKit)
            let data = image.pngData()
            #else
            let data: Data? = nil
            #endif
            return BrowserActionOutput(
                summary: "Captured screenshot.",
                snapshot: try await snapshotText(),
                screenshotBase64: data?.base64EncodedString()
            )
        case .stop:
            ensureWebView().stopLoading()
            return BrowserActionOutput(summary: "Stopped loading.", snapshot: try await snapshotText())
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    private func navigate(to url: URL) async throws {
        ensureWebView().load(URLRequest(url: url))
        await waitForNavigation()
    }

    private func ensureWebView() -> WKWebView {
        if let webView {
            return webView
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        return webView
    }

    private func waitForNavigation() async {
        await withCheckedContinuation { continuation in
            navigationContinuation = continuation
            Task {
                do {
                    try await Task.sleep(nanoseconds: 8_000_000_000)
                } catch {
                    return
                }
                if let navigationContinuation {
                    navigationContinuation.resume()
                    self.navigationContinuation = nil
                }
            }
        }
    }

    private func snapshotText() async throws -> String {
        try await evaluateJavaScriptString(
            """
            (() => {
              const title = document.title || '';
              const url = location.href;
              const text = (document.body?.innerText || '').replace(/\\s+/g, ' ').trim();
              return [url, title, text.slice(0, 8000)].filter(Boolean).join('\\n');
            })();
            """
        )
    }

    private func evaluateJavaScript(_ script: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ensureWebView().evaluateJavaScript(script) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func evaluateJavaScriptString(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            ensureWebView().evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? String ?? "")
                }
            }
        }
    }

    private func takeSnapshot(configuration: WKSnapshotConfiguration) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            ensureWebView().takeSnapshot(with: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: AgentError.permissionDenied("Browser screenshot failed."))
                }
            }
        }
    }

    private static func jsString(_ string: String) -> String {
        do {
            let data = try JSONEncoder().encode(string)
            return String(decoding: data, as: UTF8.self)
        } catch {
            browserRuntimeLogger.error("Failed to encode browser JavaScript string: \(error.localizedDescription, privacy: .public)")
            return "\"\""
        }
    }
}
