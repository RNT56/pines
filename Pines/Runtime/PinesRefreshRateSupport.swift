import SwiftUI

#if os(iOS)
import QuartzCore
import UIKit

enum PinesRefreshRatePolicy {
    static let baselineFramesPerSecond = 60

    static func supportsHighRefresh(maximumFramesPerSecond: Int) -> Bool {
        maximumFramesPerSecond > baselineFramesPerSecond
    }

    static func preferredFrameRateRange(maximumFramesPerSecond: Int) -> CAFrameRateRange {
        guard supportsHighRefresh(maximumFramesPerSecond: maximumFramesPerSecond) else {
            return .default
        }

        let maximum = Float(maximumFramesPerSecond)
        return CAFrameRateRange(
            minimum: Float(baselineFramesPerSecond),
            maximum: maximum,
            preferred: maximum
        )
    }
}

extension View {
    @ViewBuilder
    func pinesHighRefreshRate() -> some View {
        if #available(iOS 18.0, *) {
            background {
                PinesHighRefreshRateHost()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        } else {
            self
        }
    }
}

@available(iOS 18.0, *)
private struct PinesHighRefreshRateHost: UIViewRepresentable {
    func makeUIView(context: Context) -> PinesHighRefreshRateView {
        let view = PinesHighRefreshRateView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: PinesHighRefreshRateView, context: Context) {
        uiView.refreshPreferredFrameRate()
    }
}

@available(iOS 18.0, *)
private final class PinesHighRefreshRateView: UIView {
    private weak var linkedWindow: UIWindow?
    private var updateLink: UIUpdateLink?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshPreferredFrameRate()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        refreshPreferredFrameRate()
    }

    func refreshPreferredFrameRate() {
        guard let window else {
            updateLink?.isEnabled = false
            linkedWindow = nil
            updateLink = nil
            return
        }

        let maximumFramesPerSecond = window.screen.maximumFramesPerSecond
        guard PinesRefreshRatePolicy.supportsHighRefresh(maximumFramesPerSecond: maximumFramesPerSecond) else {
            updateLink?.isEnabled = false
            updateLink = nil
            linkedWindow = nil
            return
        }

        let link: UIUpdateLink
        if let existing = updateLink, linkedWindow === window {
            link = existing
        } else {
            updateLink?.isEnabled = false
            link = UIUpdateLink(view: self)
            updateLink = link
            linkedWindow = window
        }

        // Keep the link passive. iOS traps if continuous-update flags are set without phase actions.
        link.preferredFrameRateRange = PinesRefreshRatePolicy.preferredFrameRateRange(
            maximumFramesPerSecond: maximumFramesPerSecond
        )
        link.isEnabled = true
    }

    deinit {
        MainActor.assumeIsolated {
            updateLink?.isEnabled = false
        }
    }
}
#endif
