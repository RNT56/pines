import SwiftUI
import PinesCore

struct ModelSidebarList: View {
    @Environment(\.pinesTheme) private var theme
    @Binding var selectedModelID: PinesModelPreview.ID?
    @Binding var selectedTaskFilter: HubTask?
    @Binding var selectedVerificationFilter: ModelVerificationState?
    @Binding var selectedInstallStateFilter: ModelInstallState?
    let models: [PinesModelPreview]
    let defaultModelID: ModelID?
    let isSearching: Bool
    let searchError: String?
    let sectionTitle: String
    let isDiscovering: Bool

    var body: some View {
        List(selection: $selectedModelID) {
            Section {
                ModelFilterControls(
                    selectedTask: $selectedTaskFilter,
                    selectedVerification: $selectedVerificationFilter,
                    selectedInstallState: $selectedInstallStateFilter,
                    isSearching: isSearching
                )
                .pinesSidebarListRow(
                    insets: EdgeInsets(
                        top: theme.spacing.small,
                        leading: theme.spacing.medium,
                        bottom: theme.spacing.small,
                        trailing: theme.spacing.medium
                    ),
                    background: theme.colors.sidebarBackground
                )
            }

            Section {
                statusRows

                ModelRows(
                    models: models,
                    defaultModelID: defaultModelID,
                    selectedModelID: selectedModelID
                )
            } header: {
                ModelResultsHeader(
                    title: sectionTitle,
                    count: models.count,
                    isDiscovering: isDiscovering
                )
            }
        }
    }

    @ViewBuilder
    private var statusRows: some View {
        if isSearching {
            ModelListStatusRow(
                title: "Searching Hugging Face",
                detail: "Checking MLX metadata",
                systemImage: "magnifyingglass",
                showsProgress: true
            )
        }

        if let searchError {
            ModelListStatusRow(
                title: "Search failed",
                detail: searchError,
                systemImage: "exclamationmark.triangle.fill",
                tint: theme.colors.warning
            )
        } else if !isSearching, models.isEmpty {
            ModelListStatusRow(
                title: isDiscovering ? "No matching MLX models" : "No installed models",
                detail: isDiscovering ? "Try a different query or filter" : "Search Hugging Face to find compatible MLX models",
                systemImage: "magnifyingglass"
            )
        }
    }
}

private struct ModelRows: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    let models: [PinesModelPreview]
    let defaultModelID: ModelID?
    let selectedModelID: PinesModelPreview.ID?

    var body: some View {
        ForEach(models) { model in
            ModelRow(
                model: model,
                isDefault: defaultModelID == model.install.modelID,
                isSelected: selectedModelID == model.id
            )
            .tag(model.id)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if model.canStartDownload {
                    Button {
                        haptics.play(.primaryAction)
                        Task {
                            await appModel.installModel(repository: model.install.repository, services: services)
                        }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .tint(theme.colors.accent)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if model.hasActiveDownload {
                    Button(role: .destructive) {
                        haptics.play(.destructiveAction)
                        Task {
                            await appModel.cancelModelDownload(repository: model.install.repository, services: services)
                        }
                    } label: {
                        Label("Cancel", systemImage: "stop.circle")
                    }
                } else if model.canDeleteModel {
                    Button(role: .destructive) {
                        haptics.play(.destructiveAction)
                        Task {
                            await appModel.deleteModel(repository: model.install.repository, services: services)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
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
        .pinesSidebarListRow(
            insets: EdgeInsets(
                top: theme.spacing.xxsmall,
                leading: theme.spacing.xsmall,
                bottom: theme.spacing.xxsmall,
                trailing: theme.spacing.xsmall
            )
        )
    }
}

private struct ModelRow: View {
    @Environment(\.pinesTheme) private var theme
    let model: PinesModelPreview
    let isDefault: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            PinesSidebarRow(
                title: model.name,
                subtitle: "\(model.family) - \(model.footprint) - \(model.contextWindow)",
                systemImage: model.status.systemImage,
                detail: isDefault ? "Default" : model.status.title,
                tint: model.status.tint(in: theme),
                isSelected: isSelected,
                isActive: model.status == .indexing || model.install.state == .downloading
            ) {
                PinesStatusIndicator(
                    color: model.status.tint(in: theme),
                    isActive: model.status == .indexing || model.install.state == .downloading,
                    size: 9
                )
            }
            if let progress = model.downloadProgress, progress.isActive {
                PinesProgressBar(value: progress.fractionCompleted)
                    .padding(.horizontal, theme.spacing.small)
                Text(progress.currentFile ?? progress.status.title)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, theme.spacing.small)
            }
        }
        .pinesSidebarListRow()
    }
}

private enum ModelDetailAction: Hashable {
    case download
    case cancel
    case use
    case delete
}

private struct ModelActionLabel: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let systemImage: String
    let isPending: Bool

    var body: some View {
        HStack(spacing: theme.spacing.xsmall) {
            if isPending {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
            }

            Text(title)
        }
        .contentTransition(.opacity)
    }
}

struct ModelDetailView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    let model: PinesModelPreview
    @State private var pendingAction: ModelDetailAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                headerCard
                actionsCard
                readinessCard
                runtimeProfileCard
                deviceCard
                repositoryCard
                capabilitiesCard

                if !model.compatibilityWarnings.isEmpty {
                    compatibilityCard
                }
            }
            .padding(theme.spacing.large)
            .frame(maxWidth: theme.spacing.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.name)
        .pinesExpressiveScrollHaptics()
        .pinesInlineNavigationTitle()
        .pinesAppBackground()
        .task(id: model.install.repository) {
            guard model.install.state == .remote else { return }
            await appModel.preflightModel(repository: model.install.repository, services: services)
        }
        .onChange(of: model.hasActiveDownload) { _, isActive in
            if isActive, pendingAction == .download {
                pendingAction = nil
            }
        }
        .onChange(of: model.install.state) { _, _ in
            if pendingAction != .download {
                pendingAction = nil
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: theme.dashboard.wideGridMinWidth), spacing: theme.spacing.small)]
    }

    private var headerCard: some View {
        PinesCardSection(model.name, subtitle: "\(model.family) model for \(model.runtime)", systemImage: model.status.systemImage, kind: .glass) {
            HStack(alignment: .center, spacing: theme.spacing.large) {
                PinesReadinessRing(value: model.readiness, title: "Ready", subtitle: model.status.title)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: theme.dashboard.compactGridMinWidth), spacing: theme.spacing.small)], spacing: theme.spacing.small) {
                    PinesInfoTile(title: "Status", value: model.status.title, systemImage: model.status.systemImage, tint: model.status.tint(in: theme))
                    PinesInfoTile(title: "Footprint", value: model.footprint, systemImage: "externaldrive")
                    PinesInfoTile(title: "Context", value: model.contextWindow, systemImage: "text.word.spacing")
                    if appModel.defaultModelID == model.install.modelID {
                        PinesInfoTile(title: "Default", value: "Selected", systemImage: "checkmark.circle", tint: theme.colors.success)
                    }
                }
            }
        }
        .background {
            PinesAmbientBackground()
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous))
                .opacity(0.42)
        }
    }

    private var actionsCard: some View {
        PinesCardSection("Actions", subtitle: "Install, select, or remove this model.", systemImage: "bolt.circle") {
            VStack(alignment: .leading, spacing: theme.spacing.medium) {
                HStack(spacing: theme.spacing.medium) {
                    PinesStatusIndicator(
                        color: model.status.tint(in: theme),
                        isActive: model.hasActiveDownload,
                        size: 10
                    )

                    VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                        Text(actionStatusTitle)
                            .font(theme.typography.headline)
                            .pinesFittingText()

                        Text(actionStatusDetail)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)
                    }

                    Spacer(minLength: theme.spacing.small)

                    Text(model.install.state.title)
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(model.status.tint(in: theme))
                        .padding(.horizontal, theme.spacing.small)
                        .frame(minHeight: theme.dashboard.chipHeight)
                        .background(model.status.tint(in: theme).opacity(0.12), in: Capsule())
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .pinesSurface(.inset, padding: theme.spacing.small)

                if let progress = model.downloadProgress, progress.isActive {
                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        PinesProgressBar(value: progress.fractionCompleted, tint: model.status.tint(in: theme))
                            .animation(theme.motion.progressUpdate, value: progress.fractionCompleted)

                        Text(progress.progressLabel)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }

                if model.hasActiveDownload {
                    Button(role: .destructive) {
                        runAction(.cancel) {
                            await appModel.cancelModelDownload(repository: model.install.repository, services: services)
                        }
                    } label: {
                        ModelActionLabel(
                            title: pendingAction == .cancel ? "Cancelling" : "Cancel download",
                            systemImage: "stop.circle",
                            isPending: pendingAction == .cancel
                        )
                    }
                    .pinesButtonStyle(.destructive, fillWidth: true)
                    .disabled(pendingAction != nil)
                } else {
                    HStack(spacing: theme.spacing.small) {
                        if model.canChooseInstallMode {
                            Menu {
                                Button("Text only", systemImage: "text.bubble") {
                                    runAction(.download) {
                                        await appModel.installModel(
                                            repository: model.install.repository,
                                            mode: .textOnly,
                                            services: services
                                        )
                                    }
                                }
                                Button("Text + Vision", systemImage: "eye") {
                                    runAction(.download) {
                                        await appModel.installModel(
                                            repository: model.install.repository,
                                            mode: .full,
                                            services: services
                                        )
                                    }
                                }
                            } label: {
                                ModelActionLabel(
                                    title: pendingAction == .download ? "Starting" : "Download",
                                    systemImage: "arrow.down.circle",
                                    isPending: pendingAction == .download
                                )
                            }
                            .pinesButtonStyle(.primary, fillWidth: true)
                            .disabled(model.install.state == .installed || model.status == .unsupported || pendingAction != nil)
                        } else {
                            Button {
                                runAction(.download) {
                                    await appModel.installModel(repository: model.install.repository, services: services)
                                }
                            } label: {
                                ModelActionLabel(
                                    title: pendingAction == .download ? "Starting" : "Download",
                                    systemImage: "arrow.down.circle",
                                    isPending: pendingAction == .download
                                )
                            }
                            .pinesButtonStyle(.primary, fillWidth: true)
                            .disabled(model.install.state == .installed || model.status == .unsupported || pendingAction != nil)
                        }

                        Button {
                            runAction(.use) {
                                await appModel.selectDefaultModel(model, services: services)
                            }
                        } label: {
                            ModelActionLabel(
                                title: pendingAction == .use ? "Selecting" : (isDefaultModel ? "Default" : "Use"),
                                systemImage: isDefaultModel ? "checkmark.seal.fill" : "checkmark.circle",
                                isPending: pendingAction == .use
                            )
                        }
                        .pinesButtonStyle(.secondary, fillWidth: true)
                        .disabled(model.install.state != .installed || isDefaultModel || pendingAction != nil)
                    }
                }

                Button(role: .destructive) {
                    runAction(.delete) {
                        await appModel.deleteModel(repository: model.install.repository, services: services)
                    }
                } label: {
                    ModelActionLabel(
                        title: pendingAction == .delete ? "Deleting" : (model.hasActiveDownload ? "Remove download" : "Delete model"),
                        systemImage: "trash",
                        isPending: pendingAction == .delete
                    )
                }
                .pinesButtonStyle(.destructive, fillWidth: true)
                .disabled(!model.canDeleteModel || pendingAction != nil)
            }
            .animation(theme.motion.fast, value: pendingAction)
        }
    }

    private func runAction(_ action: ModelDetailAction, operation: @escaping () async -> Void) {
        guard pendingAction == nil else { return }
        pendingAction = action
        haptics.play(action == .delete || action == .cancel ? .destructiveAction : .primaryAction)

        Task {
            await operation()
            await MainActor.run {
                if pendingAction == action {
                    pendingAction = nil
                }
            }
        }
    }

    private var isDefaultModel: Bool {
        appModel.defaultModelID == model.install.modelID
    }

    private var actionStatusTitle: String {
        if model.hasActiveDownload {
            return model.downloadProgress?.status.title ?? "Downloading"
        }
        if isDefaultModel {
            return "Default model"
        }
        return model.status.title
    }

    private var actionStatusDetail: String {
        if let progress = model.downloadProgress, progress.isActive {
            return [progress.currentFile, progress.progressLabel].compactMap(\.self).joined(separator: " - ")
        }
        if model.status == .unsupported {
            return "This model is not compatible with the current runtime profile."
        }
        if model.install.state == .installed {
            return isDefaultModel ? "Pines will use this model for new local chat sessions." : "Installed locally and ready to use."
        }
        return "Available from Hugging Face and ready to download when compatible."
    }

    private var readinessCard: some View {
        PinesCardSection("Install Timeline", subtitle: model.downloadProgress?.progressLabel ?? model.install.state.title, systemImage: "arrow.down.doc") {
            if let progress = model.downloadProgress, progress.isActive {
                PinesProgressBar(value: progress.fractionCompleted)
                    .animation(theme.motion.progressUpdate, value: progress.fractionCompleted)
            }

            PinesTimeline(items: installTimelineItems)
        }
    }

    private var installTimelineItems: [PinesTimelineItem] {
        let progress = model.downloadProgress
        var items = [
            PinesTimelineItem(
                title: "Repository",
                detail: model.install.repository,
                systemImage: "shippingbox",
                tint: theme.colors.accent,
                isCurrent: false
            ),
            PinesTimelineItem(
                title: "Compatibility",
                detail: model.install.verification.title,
                systemImage: "checkmark.seal",
                tint: model.install.verification.tint(in: theme),
                isCurrent: false
            )
        ]
        if let progress {
            items.append(PinesTimelineItem(
                title: progress.status.title,
                detail: [progress.progressLabel, progress.currentFile].compactMap(\.self).joined(separator: "\n"),
                systemImage: progress.isActive ? "arrow.down.circle" : "checkmark.circle",
                tint: progress.status.tint(in: theme),
                isCurrent: progress.isActive
            ))
        } else {
            items.append(PinesTimelineItem(
                title: model.install.state.title,
                detail: model.status.title,
                systemImage: model.install.state == .installed ? "checkmark.circle" : "circle.dashed",
                tint: model.status.tint(in: theme),
                isCurrent: model.install.state == .downloading
            ))
        }
        return items
    }

    private var runtimeProfileCard: some View {
        PinesCardSection("Runtime Profile", subtitle: "Execution profile, KV cache, backend, and Metal path.", systemImage: "cpu") {
            PinesKeyValueGrid(items: runtimeItems)
        }
    }

    private var runtimeItems: [PinesKeyValueGrid.Item] {
        let quantization = model.runtimeProfile.quantization
        var items: [PinesKeyValueGrid.Item] = [
            .init("Runtime", model.runtime, systemImage: "cpu"),
            .init("Profile", model.runtimeProfile.name, systemImage: "slider.horizontal.3"),
            .init("KV cache", quantization.algorithm.title, systemImage: "memorychip"),
            .init("Metal codec", quantization.metalCodecAvailable ? "Available" : "Unavailable", systemImage: "bolt.horizontal"),
            .init("Metal attention", quantization.metalAttentionAvailable ? "Available" : "Unavailable", systemImage: "scope"),
            .init("Optimization", quantization.turboQuantOptimizationPolicy.displayName, systemImage: "gauge")
        ]
        if let preset = quantization.preset { items.append(.init("KV preset", preset.displayName)) }
        if let requestedBackend = quantization.requestedBackend { items.append(.init("Requested backend", requestedBackend.displayName)) }
        if let activeBackend = quantization.activeBackend { items.append(.init("Active backend", activeBackend.displayName)) }
        if let attentionPath = quantization.activeAttentionPath { items.append(.init("Attention path", attentionPath.displayName)) }
        if let kernelProfile = quantization.metalKernelProfile { items.append(.init("Kernel", kernelProfile.displayName)) }
        if let selfTest = quantization.metalSelfTestStatus { items.append(.init("MLX self-test", selfTest.displayName)) }
        if let rawFallbackAllocated = quantization.rawFallbackAllocated { items.append(.init("Raw KV fallback", rawFallbackAllocated ? "Allocated" : "Not allocated")) }
        if quantization.thermalDownshiftActive { items.append(.init("Thermal downshift", "Active")) }
        if let unsupportedShape = quantization.lastUnsupportedAttentionShape { items.append(.init("Unsupported shape", unsupportedShape, copyable: true)) }
        if let fallback = quantization.activeFallbackReason { items.append(.init("Fallback", fallback, copyable: true)) }
        return items
    }

    private var deviceCard: some View {
        PinesCardSection("Device", subtitle: "Memory, thermal, and context guidance for this runtime.", systemImage: "iphone.gen3") {
            PinesKeyValueGrid(items: deviceItems)
        }
    }

    private var deviceItems: [PinesKeyValueGrid.Item] {
        let quantization = model.runtimeProfile.quantization
        let memory = quantization.memoryCounters
        var items: [PinesKeyValueGrid.Item] = []
        if let performanceClass = quantization.devicePerformanceClass { items.append(.init("Performance", performanceClass.displayName, systemImage: "speedometer")) }
        if let contextTokens = memory.recommendedContextTokens { items.append(.init("Context", "\(contextTokens.formatted()) tokens", systemImage: "text.word.spacing")) }
        if let thermalState = memory.thermalState { items.append(.init("Thermal state", thermalState.capitalized, systemImage: "thermometer.medium")) }
        if let physicalMemory = memory.physicalMemoryBytes { items.append(.init("Device memory", ByteCountFormatter.string(fromByteCount: physicalMemory, countStyle: .memory), systemImage: "memorychip")) }
        if let availableMemory = memory.availableMemoryBytes { items.append(.init("Available memory", ByteCountFormatter.string(fromByteCount: availableMemory, countStyle: .memory))) }
        if let workingSet = memory.metalRecommendedWorkingSetBytes { items.append(.init("MLX working set", ByteCountFormatter.string(fromByteCount: workingSet, countStyle: .memory))) }
        if let hardware = memory.hardwareModelIdentifier { items.append(.init("Device identifier", hardware, copyable: true)) }
        if let metalArchitecture = memory.metalArchitectureName { items.append(.init("Metal architecture", metalArchitecture)) }
        if let lowPower = memory.lowPowerModeEnabled { items.append(.init("Low Power Mode", lowPower ? "On" : "Off")) }
        return items.isEmpty ? [.init("Diagnostics", "Pending", systemImage: "hourglass")] : items
    }

    private var repositoryCard: some View {
        PinesCardSection("Repository", subtitle: "Source metadata used by the model installer.", systemImage: "shippingbox") {
            PinesKeyValueGrid(items: repositoryItems)
        }
    }

    private var repositoryItems: [PinesKeyValueGrid.Item] {
        var items: [PinesKeyValueGrid.Item] = [
            .init("Repository", model.install.repository, systemImage: "link", copyable: true)
        ]
        if let revision = model.install.revision { items.append(.init("Revision", revision, copyable: true)) }
        if let license = model.install.license { items.append(.init("License", license, systemImage: "doc.text")) }
        return items
    }

    private var capabilitiesCard: some View {
        PinesCardSection("Capabilities", subtitle: "Modalities and hub metadata grouped into stable chips.", systemImage: "square.grid.2x2") {
            FlowPills(items: model.capabilities.isEmpty ? ["metadata pending"] : model.capabilities)
        }
    }

    private var compatibilityCard: some View {
        PinesCardSection("Compatibility", subtitle: "Warnings surfaced before install or execution.", systemImage: "exclamationmark.triangle") {
            ForEach(model.compatibilityWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(theme.typography.callout)
                    .foregroundStyle(model.install.verification == .unsupported ? theme.colors.danger : theme.colors.warning)
                    .lineLimit(3)
                    .minimumScaleFactor(0.86)
                    .pinesSurface(.inset, padding: theme.spacing.small)
            }
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

    func tint(in theme: PinesTheme) -> Color {
        switch self {
        case .verified:
            theme.colors.success
        case .installable:
            theme.colors.accent
        case .experimental:
            theme.colors.warning
        case .unsupported:
            theme.colors.danger
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

extension PinesModelPreview {
    var hasActiveDownload: Bool {
        downloadProgress?.isActive == true || install.state == .downloading || status == .indexing
    }

    var canDeleteModel: Bool {
        hasActiveDownload || install.state != .remote || downloadProgress != nil
    }

    var canStartDownload: Bool {
        install.state != .installed && !hasActiveDownload && status != .unsupported
    }

    var canChooseInstallMode: Bool {
        canStartDownload
            && install.modalities.contains(.text)
            && install.modalities.contains(.vision)
            && !install.modalities.contains(.embeddings)
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

    func tint(in theme: PinesTheme) -> Color {
        switch self {
        case .installed:
            theme.colors.success
        case .failed:
            theme.colors.danger
        case .cancelled:
            theme.colors.tertiaryText
        case .queued, .downloading, .verifying, .installing:
            theme.colors.info
        }
    }
}
