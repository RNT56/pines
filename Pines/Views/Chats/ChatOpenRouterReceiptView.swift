import PinesCore
import SwiftUI

struct ChatOpenRouterReceiptView: View {
    @Environment(\.pinesTheme) private var theme
    @State private var isExpanded = false
    let provenance: OpenRouterRunProvenance

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                if let route = routeDetail {
                    receiptRow("Route", value: route)
                }
                if let attempts = attemptDetail {
                    receiptRow("Attempts", value: attempts)
                }
                if let model = provenance.model {
                    receiptRow("Model", value: model)
                }
                if let usage = usageDetail {
                    receiptRow("Usage", value: usage)
                }
                if let cost = costDetail {
                    receiptRow("Cost", value: cost)
                }
                if let execution = executionDetail {
                    receiptRow("Execution", value: execution)
                }
                if let routeSummary = provenance.routeSummary {
                    receiptRow("Router", value: routeSummary)
                }
                if let generationID = provenance.generationID {
                    receiptRow("Generation", value: generationID, monospaced: true)
                }
            }
            .padding(.top, theme.spacing.small)
        } label: {
            HStack(spacing: theme.spacing.xsmall) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.info)
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("OpenRouter receipt")
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)

                    if let summary = collapsedSummary {
                        Text(summary)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
        .tint(theme.colors.accent)
        .padding(.vertical, theme.spacing.xsmall)
        .padding(.horizontal, theme.spacing.small)
        .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)
        }
        .accessibilityIdentifier("pines.chat.openrouter-receipt")
        .accessibilityLabel(accessibilitySummary)
    }

    private var collapsedSummary: String? {
        [
            provenance.selectedProvider,
            provenance.costCredits.map { "\(Self.formattedCredits($0)) credits" },
            provenance.totalTokens.map { "\($0) tokens" },
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
        .nilIfEmpty
    }

    private var routeDetail: String? {
        var components = [String]()
        if let provider = provenance.selectedProvider {
            components.append(provider)
        }
        if let strategy = provenance.strategy {
            components.append(strategy.replacingOccurrences(of: "_", with: " "))
        }
        if let attempts = provenance.effectiveAttemptCount {
            components.append(attempts == 1 ? "1 attempt" : "\(attempts) attempts")
        }
        return components.joined(separator: " - ").nilIfEmpty
    }

    private var usageDetail: String? {
        var components = [String]()
        if let promptTokens = provenance.promptTokens {
            components.append("\(promptTokens) input")
        }
        if let completionTokens = provenance.completionTokens {
            components.append("\(completionTokens) output")
        }
        if let totalTokens = provenance.totalTokens {
            components.append("\(totalTokens) total")
        }
        return components.joined(separator: " - ").nilIfEmpty
    }

    private var attemptDetail: String? {
        guard !provenance.routeAttempts.isEmpty else { return nil }
        return provenance.routeAttempts.map { attempt in
            var label = attempt.provider ?? attempt.model ?? "Provider"
            if let status = attempt.status {
                label += " (\(status))"
            }
            return label
        }
        .joined(separator: " -> ")
        .nilIfEmpty
    }

    private var costDetail: String? {
        guard let cost = provenance.costCredits else { return nil }
        var detail = "\(Self.formattedCredits(cost)) credits"
        if let upstreamCost = provenance.upstreamInferenceCost {
            detail += " - \(Self.formattedCredits(upstreamCost)) upstream"
        }
        if let isBYOK = provenance.isBYOK {
            detail += isBYOK ? " - BYOK" : " - OpenRouter credits"
        }
        return detail
    }

    private var executionDetail: String? {
        var components = [String]()
        if let region = provenance.region {
            components.append(region.uppercased())
        }
        if let serviceTier = provenance.serviceTier {
            components.append(serviceTier.replacingOccurrences(of: "_", with: " "))
        }
        if let nativeFinishReason = provenance.nativeFinishReason {
            components.append("finished \(nativeFinishReason.replacingOccurrences(of: "_", with: " "))")
        }
        return components.joined(separator: " - ").nilIfEmpty
    }

    private var accessibilitySummary: String {
        ["OpenRouter run receipt", collapsedSummary, routeDetail]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    @ViewBuilder
    private func receiptRow(_ label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.small) {
            Text(label)
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .frame(width: 68, alignment: .leading)

            Text(value)
                .font(monospaced ? theme.typography.caption.monospaced() : theme.typography.caption)
                .foregroundStyle(theme.colors.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func formattedCredits(_ value: Double) -> String {
        let fractionDigits: Int
        switch value {
        case 1...:
            fractionDigits = 4
        case 0.01...:
            fractionDigits = 6
        default:
            fractionDigits = 8
        }
        let formatted = String(format: "%.*f", fractionDigits, value)
        return formatted
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
