import SwiftUI
import PinesCore

struct ModelsView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var selectedModelID: PinesModelPreview.ID?
    @State private var searchText = ""
    @State private var selectedTaskFilter: HubTask?
    @State private var selectedVerificationFilter: ModelVerificationState?
    @State private var selectedInstallStateFilter: ModelInstallState?

    private var selectedModel: PinesModelPreview? {
        guard let selectedModelID else {
            return appModel.models.first
        }

        return appModel.models.first { $0.id == selectedModelID }
    }

    private var searchFingerprint: String {
        [
            searchText,
            selectedTaskFilter?.rawValue ?? "all",
            selectedVerificationFilter?.rawValue ?? "all",
            selectedInstallStateFilter?.rawValue ?? "all",
        ].joined(separator: "|")
    }

    private var isDiscovering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedTaskFilter != nil
            || selectedVerificationFilter != nil
            || selectedInstallStateFilter != nil
    }

    private var modelSectionTitle: String {
        if appModel.isSearchingModels {
            return "Searching Hugging Face"
        }
        return isDiscovering ? "MLX Hub results" : "Recommended models"
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedModelID) {
                Section {
                    ModelFilterControls(
                        selectedTask: $selectedTaskFilter,
                        selectedVerification: $selectedVerificationFilter,
                        selectedInstallState: $selectedInstallStateFilter,
                        isSearching: appModel.isSearchingModels
                    )
                    .listRowInsets(EdgeInsets(top: theme.spacing.small, leading: theme.spacing.medium, bottom: theme.spacing.small, trailing: theme.spacing.medium))
                    .listRowBackground(Color.clear)
                }

                Section {
                    if appModel.isSearchingModels {
                        ModelListStatusRow(
                            title: "Searching Hugging Face",
                            detail: "Checking MLX metadata",
                            systemImage: "magnifyingglass",
                            showsProgress: true
                        )
                    }

                    if let error = appModel.modelSearchError {
                        ModelListStatusRow(
                            title: "Search failed",
                            detail: error,
                            systemImage: "exclamationmark.triangle.fill",
                            tint: theme.colors.warning
                        )
                    } else if !appModel.isSearchingModels, appModel.models.isEmpty {
                        ModelListStatusRow(
                            title: "No matching MLX models",
                            detail: "Try a different query or filter",
                            systemImage: "magnifyingglass"
                        )
                    }

                    ForEach(appModel.models) { model in
                        ModelRow(model: model, isDefault: appModel.defaultModelID == model.install.modelID)
                            .tag(model.id)
                    }
                } header: {
                    ModelResultsHeader(
                        title: modelSectionTitle,
                        count: appModel.models.count,
                        isDiscovering: isDiscovering
                    )
                }
            }
            .navigationTitle("Models")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        if let selectedModel {
                            haptics.play(.primaryAction)
                            Task {
                                await appModel.selectDefaultModel(selectedModel, services: services)
                            }
                        }
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .accessibilityLabel("Use as default model")
                    .disabled(selectedModel?.install.state != .installed)

                    Button {
                        if let selectedModel {
                            haptics.play(.primaryAction)
                            Task {
                                await appModel.installModel(repository: selectedModel.install.repository, services: services)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .accessibilityLabel("Download model")
                    .disabled(selectedModel == nil || selectedModel?.install.state == .installed || selectedModel?.status == .indexing || selectedModel?.status == .unsupported)

                    Button(role: .destructive) {
                        if let selectedModel {
                            haptics.play(.destructiveAction)
                            Task {
                                await appModel.deleteModel(repository: selectedModel.install.repository, services: services)
                            }
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete model")
                    .disabled(selectedModel?.install.state == .remote || selectedModel == nil)
                }
            }
            .searchable(text: $searchText, prompt: "Search Hugging Face")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .task(id: searchFingerprint) {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await appModel.searchModels(
                    query: searchText,
                    task: selectedTaskFilter,
                    verification: selectedVerificationFilter,
                    installState: selectedInstallStateFilter,
                    services: services
                )
            }
            .onAppear {
                selectedModelID = selectedModelID ?? appModel.models.first?.id
            }
            .onChange(of: selectedModelID) { _, _ in
                haptics.play(.navigationSelected)
            }
            .onChange(of: appModel.models) { _, models in
                guard !models.contains(where: { $0.id == selectedModelID }) else { return }
                selectedModelID = models.first?.id
            }
            .scrollContentBackground(.hidden)
            .background(theme.colors.secondaryBackground)
            .animation(theme.motion.fast, value: appModel.isSearchingModels)
            .animation(theme.motion.fast, value: appModel.models)
        } detail: {
            if let selectedModel {
                ModelDetailView(model: selectedModel)
            } else {
                PinesEmptyState(
                    title: "No models",
                    detail: "Search Hugging Face or install a curated local MLX model.",
                    systemImage: "cpu"
                )
            }
        }
    }
}

private struct ModelFilterControls: View {
    @Environment(\.pinesTheme) private var theme
    @Binding var selectedTask: HubTask?
    @Binding var selectedVerification: ModelVerificationState?
    @Binding var selectedInstallState: ModelInstallState?
    let isSearching: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: theme.spacing.small) {
                Menu {
                    Button("All tasks") { selectedTask = nil }
                    ForEach(HubTask.allCases, id: \.self) { task in
                        Button(task.title) { selectedTask = task }
                    }
                } label: {
                    Label(selectedTask?.title ?? "All tasks", systemImage: selectedTask?.systemImage ?? "line.3.horizontal.decrease.circle")
                }
                .pinesButtonStyle(.secondary)

                Menu {
                    Button("All compatibility") { selectedVerification = nil }
                    ForEach(ModelVerificationState.allCases, id: \.self) { state in
                        Button(state.title) { selectedVerification = state }
                    }
                } label: {
                    Label(selectedVerification?.title ?? "Compatibility", systemImage: "checkmark.seal")
                }
                .pinesButtonStyle(.secondary)

                Menu {
                    Button("Any state") { selectedInstallState = nil }
                    ForEach(ModelInstallState.allCases, id: \.self) { state in
                        Button(state.title) { selectedInstallState = state }
                    }
                } label: {
                    Label(selectedInstallState?.title ?? "State", systemImage: "externaldrive.badge.checkmark")
                }
                .pinesButtonStyle(.secondary)

                if isSearching {
                    PinesStatusIndicator(color: theme.colors.accent, isActive: true, size: 9)
                        .padding(.horizontal, theme.spacing.xsmall)
                }
            }
        }
        .scrollIndicators(.hidden)
        .font(theme.typography.caption.weight(.medium))
    }
}

private struct ModelResultsHeader: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let count: Int
    let isDiscovering: Bool

    var body: some View {
        HStack(spacing: theme.spacing.small) {
            Text(title)
            Spacer(minLength: theme.spacing.small)
            Text("\(count)")
                .font(theme.typography.code)
                .foregroundStyle(isDiscovering ? theme.colors.accent : theme.colors.tertiaryText)
                .padding(.horizontal, theme.spacing.xsmall)
                .padding(.vertical, theme.spacing.xxsmall)
                .background(theme.colors.controlFill, in: Capsule())
        }
    }
}

private struct ModelListStatusRow: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let detail: String
    let systemImage: String
    var showsProgress = false
    var tint: Color?

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.small) {
            if showsProgress {
                PinesStatusIndicator(color: tint ?? theme.colors.accent, isActive: true, size: 10)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint ?? theme.colors.accent)
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(title)
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.colors.primaryText)
                    .pinesFittingText()
                Text(detail)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
            }
        }
        .padding(.vertical, theme.spacing.xsmall)
    }
}

private struct ModelRow: View {
    @Environment(\.pinesTheme) private var theme
    let model: PinesModelPreview
    let isDefault: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            HStack(spacing: theme.spacing.small) {
                Text(model.name)
                    .font(theme.typography.headline)
                    .lineLimit(1)

                if isDefault {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.colors.success)
                        .accessibilityLabel("Default model")
                }

                Spacer(minLength: theme.spacing.small)

                PinesStatusIndicator(
                    color: model.status.tint(in: theme),
                    isActive: model.status == .indexing || model.install.state == .downloading,
                    size: 9
                )
            }

            Text("\(model.family) - \(model.footprint) - \(model.contextWindow)")
                .font(theme.typography.callout)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if let progress = model.downloadProgress, progress.isActive {
                PinesProgressBar(value: progress.fractionCompleted)
                Text(progress.currentFile ?? progress.status.title)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(.vertical, theme.spacing.xsmall)
    }
}

private struct ModelDetailView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    let model: PinesModelPreview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                PinesSectionHeader(model.name, subtitle: "\(model.family) model for \(model.runtime)")

                HStack(spacing: theme.spacing.small) {
                    PinesMetricPill(title: model.status.title, systemImage: model.status.systemImage)
                    PinesMetricPill(title: model.footprint, systemImage: "externaldrive")
                    PinesMetricPill(title: model.contextWindow, systemImage: "text.word.spacing")
                    if appModel.defaultModelID == model.install.modelID {
                        PinesMetricPill(title: "Default", systemImage: "checkmark.circle")
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.82)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: theme.spacing.small)], spacing: theme.spacing.small) {
                    Button {
                        haptics.play(.primaryAction)
                        Task {
                            await appModel.installModel(repository: model.install.repository, services: services)
                        }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .pinesButtonStyle(.primary, fillWidth: true)
                    .disabled(model.install.state == .installed || model.status == .indexing || model.status == .unsupported)

                    Button {
                        haptics.play(.primaryAction)
                        Task {
                            await appModel.selectDefaultModel(model, services: services)
                        }
                    } label: {
                        Label("Use", systemImage: "checkmark.circle")
                    }
                    .pinesButtonStyle(.secondary, fillWidth: true)
                    .disabled(model.install.state != .installed)

                    Button(role: .destructive) {
                        haptics.play(.destructiveAction)
                        Task {
                            await appModel.deleteModel(repository: model.install.repository, services: services)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .pinesButtonStyle(.destructive, fillWidth: true)
                    .disabled(model.install.state == .remote)
                }

                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    HStack {
                        Text("Readiness")
                            .font(theme.typography.section)
                        Spacer()
                        Text("\(Int(model.readiness * 100))%")
                            .font(theme.typography.code)
                            .foregroundStyle(theme.colors.secondaryText)
                    }

                    PinesProgressBar(value: model.readiness)

                    if let progress = model.downloadProgress {
                        Text(progress.progressLabel)
                            .font(theme.typography.callout)
                            .foregroundStyle(theme.colors.secondaryText)
                    }

                    LabeledContent("Runtime", value: model.runtime)
                    LabeledContent("Profile", value: model.runtimeProfile.name)
                    LabeledContent("KV cache", value: model.runtimeProfile.quantization.algorithm.title)
                    if let preset = model.runtimeProfile.quantization.preset {
                        LabeledContent("KV preset", value: preset.displayName)
                    }
                    if let requestedBackend = model.runtimeProfile.quantization.requestedBackend {
                        LabeledContent("Requested backend", value: requestedBackend.displayName)
                    }
                    if let activeBackend = model.runtimeProfile.quantization.activeBackend {
                        LabeledContent("Active backend", value: activeBackend.displayName)
                    }
                    LabeledContent(
                        "Metal codec",
                        value: model.runtimeProfile.quantization.metalCodecAvailable ? "Available" : "Unavailable"
                    )
                    LabeledContent(
                        "Metal attention",
                        value: model.runtimeProfile.quantization.metalAttentionAvailable ? "Available" : "Unavailable"
                    )
                    if let attentionPath = model.runtimeProfile.quantization.activeAttentionPath {
                        LabeledContent("Attention path", value: attentionPath.displayName)
                    }
                    if let performanceClass = model.runtimeProfile.quantization.devicePerformanceClass {
                        LabeledContent("Performance class", value: performanceClass.displayName)
                    }
                    if let kernelProfile = model.runtimeProfile.quantization.metalKernelProfile {
                        LabeledContent("Kernel variant", value: kernelProfile.displayName)
                    }
                    if let selfTest = model.runtimeProfile.quantization.metalSelfTestStatus {
                        LabeledContent("MLX self-test", value: selfTest.displayName)
                    }
                    LabeledContent(
                        "Optimization policy",
                        value: model.runtimeProfile.quantization.turboQuantOptimizationPolicy.displayName
                    )
                    if let rawFallbackAllocated = model.runtimeProfile.quantization.rawFallbackAllocated {
                        LabeledContent("Raw KV fallback", value: rawFallbackAllocated ? "Allocated" : "Not allocated")
                    }
                    if model.runtimeProfile.quantization.thermalDownshiftActive {
                        LabeledContent("Thermal downshift", value: "Active")
                    }
                    if let unsupportedShape = model.runtimeProfile.quantization.lastUnsupportedAttentionShape {
                        LabeledContent("Unsupported shape", value: unsupportedShape)
                    }
                    if let contextTokens = model.runtimeProfile.quantization.memoryCounters.recommendedContextTokens {
                        LabeledContent("Context window", value: "\(contextTokens.formatted()) tokens")
                    }
                    if let thermalState = model.runtimeProfile.quantization.memoryCounters.thermalState {
                        LabeledContent("Thermal state", value: thermalState.capitalized)
                    }
                    if let fallback = model.runtimeProfile.quantization.activeFallbackReason {
                        LabeledContent("Fallback", value: fallback)
                    }
                    LabeledContent("Repository", value: model.install.repository)
                    if let revision = model.install.revision {
                        LabeledContent("Revision", value: revision)
                    }
                    if let license = model.install.license {
                        LabeledContent("License", value: license)
                    }
                }
                .font(theme.typography.callout)
                .pinesSurface(.elevated)

                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    Text("Capabilities")
                        .font(theme.typography.section)

                    FlowPills(items: model.capabilities.isEmpty ? ["metadata pending"] : model.capabilities)
                }
                .pinesSurface(.panel)

                if !model.compatibilityWarnings.isEmpty {
                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        Text("Compatibility")
                            .font(theme.typography.section)
                        ForEach(model.compatibilityWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(theme.typography.callout)
                                .foregroundStyle(model.install.verification == .unsupported ? theme.colors.danger : theme.colors.warning)
                        }
                    }
                    .pinesSurface(.elevated)
                }
            }
            .padding(theme.spacing.large)
            .frame(maxWidth: theme.spacing.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.name)
        .pinesInlineNavigationTitle()
        .pinesAppBackground()
        .task(id: model.install.repository) {
            guard model.install.state == .remote else { return }
            await appModel.preflightModel(repository: model.install.repository, services: services)
        }
    }
}

private struct FlowPills: View {
    @Environment(\.pinesTheme) private var theme
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: theme.spacing.small)], alignment: .leading, spacing: theme.spacing.small) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(theme.typography.callout.weight(.medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.spacing.small)
                    .padding(.vertical, theme.spacing.xsmall)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .background(theme.colors.elevatedSurface, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                            .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)
                    }
            }
        }
    }
}

private extension QuantizationAlgorithm {
    var title: String {
        switch self {
        case .none:
            "None"
        case .mlxAffine:
            "MLX affine"
        case .turboQuant:
            "TurboQuant"
        }
    }
}

private extension HubTask {
    var title: String {
        switch self {
        case .textGeneration:
            "Text"
        case .imageTextToText:
            "Vision"
        case .featureExtraction:
            "Embeddings"
        case .sentenceSimilarity:
            "Similarity"
        }
    }

    var systemImage: String {
        switch self {
        case .textGeneration:
            "text.bubble"
        case .imageTextToText:
            "photo.on.rectangle"
        case .featureExtraction:
            "point.3.connected.trianglepath.dotted"
        case .sentenceSimilarity:
            "text.magnifyingglass"
        }
    }
}

private extension ModelInstallState {
    var title: String {
        switch self {
        case .remote:
            "Remote"
        case .downloading:
            "Downloading"
        case .installed:
            "Installed"
        case .failed:
            "Failed"
        case .unsupported:
            "Unsupported"
        }
    }
}

private extension ModelVerificationState {
    var title: String {
        switch self {
        case .verified:
            "Verified"
        case .installable:
            "Installable"
        case .experimental:
            "Experimental"
        case .unsupported:
            "Unsupported"
        }
    }
}

private extension PinesModelStatus {
    func tint(in theme: PinesTheme) -> Color {
        switch self {
        case .ready:
            theme.colors.success
        case .available:
            theme.colors.accent
        case .indexing:
            theme.colors.info
        case .failed:
            theme.colors.danger
        case .unsupported:
            theme.colors.tertiaryText
        }
    }
}

private extension ModelDownloadProgress {
    var isActive: Bool {
        switch status {
        case .queued, .downloading, .verifying, .installing:
            true
        case .installed, .failed, .cancelled:
            false
        }
    }

    var fractionCompleted: Double {
        guard let totalBytes, totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(bytesReceived) / Double(totalBytes)))
    }

    var progressLabel: String {
        let received = ByteCountFormatter.string(fromByteCount: bytesReceived, countStyle: .file)
        if let totalBytes {
            let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(status.title): \(received) of \(total)"
        }
        return "\(status.title): \(received)"
    }
}

private extension ModelDownloadStatus {
    var title: String {
        switch self {
        case .queued:
            "Queued"
        case .downloading:
            "Downloading"
        case .verifying:
            "Verifying"
        case .installing:
            "Installing"
        case .installed:
            "Installed"
        case .failed:
            "Failed"
        case .cancelled:
            "Cancelled"
        }
    }
}
