import Foundation
import ImageIO
import SwiftUI
import PinesCore
import UniformTypeIdentifiers
#if canImport(WebKit) && canImport(UIKit)
import WebKit
#endif

struct ChatsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var chatState: PinesChatState
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var selectedThreadID: PinesThreadPreview.ID?
    @State private var projectBeingRenamed: PinesProjectPreview?
    @State private var projectPendingDeletion: PinesProjectPreview?
    @State private var threadPendingDeletion: PinesThreadPreview?
    @State private var projectNameDraft = ""

    private var selectedThread: PinesThreadPreview? {
        guard let selectedThreadID = selectedThreadID ?? defaultThreadID else {
            return nil
        }

        return visibleThreads.first { $0.id == selectedThreadID }
    }

    private var defaultThreadID: PinesThreadPreview.ID? {
        shouldAutoSelectSidebarItem ? visibleThreads.first?.id : nil
    }

    private var visibleThreads: [PinesThreadPreview] {
        chatState.threads.filter { thread in
            if let selectedProjectID = chatState.selectedProjectID {
                return thread.projectID == selectedProjectID
            }
            return thread.projectID == nil
        }
    }

    private var threadIDs: [PinesThreadPreview.ID] {
        visibleThreads.map(\.id)
    }

    private var shouldAutoSelectSidebarItem: Bool {
        horizontalSizeClass != .compact
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedThreadID) {
                Section {
                    Button {
                        appModel.selectProject(nil)
                        selectedThreadID = nil
                    } label: {
                        ChatProjectRow(
                            title: "All Chats",
                            subtitle: "Personal chat space",
                            systemImage: "tray",
                            isSelected: chatState.selectedProjectID == nil
                        )
                    }
                    .buttonStyle(.plain)
                    .pinesSidebarListRow()

                    ForEach(chatState.projects) { project in
                        Button {
                            appModel.selectProject(project.id)
                            selectedThreadID = nil
                        } label: {
                            ChatProjectRow(
                                title: project.name,
                                subtitle: project.vaultEnabled ? "Project Vault on" : "Project Vault off",
                                systemImage: project.vaultEnabled ? "folder.badge.gearshape" : "folder",
                                isSelected: chatState.selectedProjectID == project.id
                            )
                        }
                        .buttonStyle(.plain)
                        .pinesSidebarListRow()
                        .contextMenu {
                            Button {
                                projectNameDraft = project.name
                                projectBeingRenamed = project
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button {
                                Task {
                                    await appModel.setProjectVaultEnabled(!project.vaultEnabled, projectID: project.id, services: services)
                                }
                            } label: {
                                Label(project.vaultEnabled ? "Disable Project Vault" : "Enable Project Vault", systemImage: "folder.badge.gearshape")
                            }
                            Divider()
                            Button(role: .destructive) {
                                projectPendingDeletion = project
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                Task {
                                    await appModel.setProjectVaultEnabled(!project.vaultEnabled, projectID: project.id, services: services)
                                }
                            } label: {
                                Label(project.vaultEnabled ? "Vault Off" : "Vault On", systemImage: project.vaultEnabled ? "folder.badge.minus" : "folder.badge.gearshape")
                            }
                            .tint(theme.colors.accent)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                projectPendingDeletion = project
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Projects")
                        .font(theme.typography.section)
                        .foregroundStyle(theme.colors.tertiaryText)
                        .textCase(nil)
                }

                Section {
                    if visibleThreads.isEmpty {
                        Button {
                            Task {
                                if let threadID = await appModel.createChat(services: services) {
                                    selectedThreadID = threadID
                                }
                            }
                        } label: {
                            PinesSidebarRow(
                                title: "Start a new chat",
                                subtitle: "Private by default, local when possible",
                                systemImage: "square.and.pencil",
                                tint: theme.colors.accent,
                                isSelected: false
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pines.chat.empty.create")
                        .pinesSidebarListRow()
                    }

                    ForEach(visibleThreads) { thread in
                        NavigationLink(value: thread.id) {
                            ChatThreadRow(thread: thread, isSelected: selectedThreadID == thread.id)
                        }
                        .accessibilityIdentifier("pines.chat.thread.row")
                        .pinesSidebarListRow()
                        .contextMenu {
                            Button("All Chats") {
                                Task { await appModel.moveThread(thread, toProject: nil, services: services) }
                            }
                            ForEach(chatState.projects) { project in
                                Button(project.name) {
                                    Task { await appModel.moveThread(thread, toProject: project.id, services: services) }
                                }
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                Task {
                                    await appModel.setThreadPinned(thread, pinned: !thread.isPinned, services: services)
                                }
                            } label: {
                                Label(thread.isPinned ? "Unpin" : "Pin", systemImage: thread.isPinned ? "pin.slash" : "pin")
                            }
                            .tint(theme.colors.accent)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                threadPendingDeletion = thread
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                Task {
                                    await appModel.setThreadArchived(thread, archived: thread.status != .archived, services: services)
                                }
                            } label: {
                                Label(thread.status == .archived ? "Restore" : "Archive", systemImage: thread.status == .archived ? "tray.and.arrow.up" : "archivebox")
                            }
                            .tint(theme.colors.warning)
                        }
                    }
                } header: {
                    Text("Recent")
                        .font(theme.typography.section)
                        .foregroundStyle(theme.colors.tertiaryText)
                        .textCase(nil)
                }
            }
            .navigationTitle("Chats")
            .pinesExpressiveScrollHaptics()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task {
                                if let threadID = await appModel.createChat(services: services) {
                                    selectedThreadID = threadID
                                }
                            }
                        } label: {
                            Label("New chat", systemImage: "square.and.pencil")
                        }

                        Button {
                            Task {
                                if let projectID = await appModel.createProject(services: services) {
                                    appModel.selectProject(projectID)
                                    selectedThreadID = nil
                                    if let project = chatState.projects.first(where: { $0.id == projectID }) {
                                        projectNameDraft = ""
                                        projectBeingRenamed = project
                                    }
                                }
                            }
                        } label: {
                            Label("New project", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create")
                    .accessibilityIdentifier("pines.chat.create")
                }
            }
            .onAppear(perform: selectDefaultThreadIfNeeded)
            .onChange(of: horizontalSizeClass) { _, _ in
                selectDefaultThreadIfNeeded()
            }
            .onChange(of: threadIDs) { _, ids in
                if let selectedThreadID, !ids.contains(selectedThreadID) {
                    self.selectedThreadID = nil
                }
                selectDefaultThreadIfNeeded()
            }
            .onChange(of: chatState.selectedProjectID) { _, _ in
                selectedThreadID = nil
                selectDefaultThreadIfNeeded()
            }
            .onChange(of: selectedThreadID) { _, _ in
                haptics.play(.navigationSelected)
            }
            .pinesSidebarListChrome()
        } detail: {
            if let selectedThread {
                ChatTranscriptView(thread: selectedThread)
            } else {
                PinesEmptyState(
                    title: "No chats",
                    detail: "Start a local chat when the inference runtime is connected.",
                    systemImage: "bubble.left.and.text.bubble.right",
                    primaryActionTitle: "New chat",
                    primaryActionSystemImage: "square.and.pencil"
                ) {
                    Task {
                        if let threadID = await appModel.createChat(services: services) {
                            selectedThreadID = threadID
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("pines.screen.chats")
        .alert(
            projectNameDraft.isEmpty ? "Name Project" : "Rename Project",
            isPresented: Binding(
                get: { projectBeingRenamed != nil },
                set: { if !$0 { projectBeingRenamed = nil } }
            )
        ) {
            TextField("Project name", text: $projectNameDraft)
            Button("Cancel", role: .cancel) {
                projectBeingRenamed = nil
            }
            Button("Save") {
                guard let project = projectBeingRenamed else { return }
                let name = projectNameDraft
                projectBeingRenamed = nil
                Task { await appModel.renameProject(project, name: name, services: services) }
            }
            .disabled(projectNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Project names can be up to 80 characters.")
        }
        .confirmationDialog(
            "Delete this project?",
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: projectPendingDeletion
        ) { project in
            Button("Delete project", role: .destructive) {
                projectPendingDeletion = nil
                Task { await appModel.deleteProject(project, services: services) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The project is removed. Its chats return to All Chats and its Vault documents return to Personal Vault.")
        }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: Binding(
                get: { threadPendingDeletion != nil },
                set: { if !$0 { threadPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: threadPendingDeletion
        ) { thread in
            Button("Delete chat", role: .destructive) {
                threadPendingDeletion = nil
                Task { await appModel.deleteThread(thread, services: services) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently deletes the local conversation and its messages. Vault documents are not deleted.")
        }
    }

    private func selectDefaultThreadIfNeeded() {
        guard shouldAutoSelectSidebarItem else { return }
        selectedThreadID = selectedThreadID ?? visibleThreads.first?.id
    }
}

private struct ChatProjectRow: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        PinesSidebarRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            detail: "",
            tint: theme.colors.accent,
            isSelected: isSelected
        )
    }
}

private struct ChatModelPickerButton: View {
    @Environment(\.openPinesModelsPage) private var openModelsPage
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var modelState: PinesModelState
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var showsModelPicker = false
    let currentProviderID: ProviderID?
    let currentModelID: ModelID?
    let fallbackLabel: String?
    var accessibilityLabel = "Chat model"
    var fillWidth = false
    var maxWidth: CGFloat?
    let select: (ModelPickerOption) async -> Void

    var body: some View {
        let sections = appModel.modelPickerSections(services: services)
        let unavailableProviders = unavailableCloudProviders(in: sections)
        let currentModelLabel = currentModelLabel(in: sections, unavailableProviders: unavailableProviders)

        Group {
            if sections.isEmpty && unavailableProviders.isEmpty {
                Button {
                    haptics.play(.navigationSelected)
                    openModelsPage()
                } label: {
                    pickerLabel(showsDisclosure: false, currentModelLabel: currentModelLabel)
                }
                .buttonStyle(.plain)
                .accessibilityValue("No models installed")
                .accessibilityHint("Opens Models")
            } else {
                Button {
                    haptics.play(.navigationSelected)
                    showsModelPicker = true
                } label: {
                    pickerLabel(showsDisclosure: true, currentModelLabel: currentModelLabel)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showsModelPicker) {
                    ChatModelPickerSheet(
                        sections: sections,
                        unavailableProviders: unavailableProviders,
                        currentProviderID: currentProviderID,
                        currentModelID: currentModelID,
                        select: select
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func pickerLabel(showsDisclosure: Bool, currentModelLabel: String) -> some View {
        let shape = Capsule()
        return HStack(spacing: theme.spacing.xsmall) {
            Text(currentModelLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.76)
            if fillWidth {
                Spacer(minLength: theme.spacing.xsmall)
            }
            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .font(theme.typography.callout.weight(.semibold))
        .foregroundStyle(showsDisclosure ? theme.colors.accent : theme.colors.secondaryText)
        .padding(.horizontal, theme.spacing.medium)
        .frame(maxWidth: fillWidth ? .infinity : maxWidth, minHeight: 44)
        .background(pickerBackgroundStyle, in: shape)
        .overlay {
            shape
                .strokeBorder(pickerBorderStyle, lineWidth: theme.stroke.hairline)
        }
        .overlay {
            shape
                .strokeBorder(theme.colors.surfaceHighlight.opacity(0.68), lineWidth: theme.stroke.hairline)
                .blendMode(.plusLighter)
        }
        .shadow(color: pickerShadowColor, radius: theme.shadow.panelRadius * 0.22, x: 0, y: theme.shadow.panelY * 0.16)
        .contentShape(shape)
    }

    private var pickerBackgroundStyle: AnyShapeStyle {
        if theme.colorScheme == .dark {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        theme.colors.elevatedSurface.opacity(0.92),
                        theme.colors.controlFill.opacity(0.94),
                        theme.colors.accentSoft.opacity(0.62)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    theme.colors.elevatedSurface.opacity(theme.template == .graphite || theme.template == .obsidian ? 0.98 : 0.94),
                    theme.colors.controlFill.opacity(0.82),
                    theme.colors.accentSoft.opacity(0.50)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var pickerBorderStyle: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    theme.colors.accent.opacity(theme.colorScheme == .dark ? 0.46 : 0.34),
                    theme.colors.controlBorder.opacity(0.94),
                    theme.colors.surfaceHighlight.opacity(theme.colorScheme == .dark ? 0.28 : 0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var pickerShadowColor: Color {
        if theme.colorScheme == .dark {
            return theme.colors.accent.opacity(0.10)
        }
        return theme.shadow.panelColor.opacity(0.18)
    }

    private func currentModelLabel(
        in sections: [ModelPickerSection],
        unavailableProviders: [CloudProviderConfiguration]
    ) -> String {
        let options = sections.flatMap(\.models)
        guard !options.isEmpty else {
            return unavailableProviders.isEmpty ? "None" : "No agent models"
        }

        if let currentProviderID,
           let currentModelID,
           let match = options.first(where: { $0.providerID == currentProviderID && $0.modelID == currentModelID }) {
            return match.displayName
        }
        if let currentModelID,
           let match = options.first(where: { $0.modelID == currentModelID }) {
            return match.displayName
        }
        if let match = options.first(where: { $0.providerID == modelState.defaultProviderID && $0.modelID == modelState.defaultModelID }) {
            return match.displayName
        }
        return fallbackLabel == "No model selected" ? "Select model" : (fallbackLabel ?? "Select model")
    }

    private func unavailableCloudProviders(in sections: [ModelPickerSection]) -> [CloudProviderConfiguration] {
        let selectableProviderIDs = Set(sections.flatMap(\.models).map(\.providerID))
        return appModel.cloudProviders
            .filter { provider in
                provider.enabledForAgents
                    && provider.capabilities.textGeneration
                    && !selectableProviderIDs.contains(provider.id)
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

}

private struct ChatModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    let sections: [ModelPickerSection]
    let unavailableProviders: [CloudProviderConfiguration]
    let currentProviderID: ProviderID?
    let currentModelID: ModelID?
    let select: (ModelPickerOption) async -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSections) { section in
                    Section(section.title) {
                        ForEach(section.models) { option in
                            Button {
                                Task {
                                    await select(option)
                                    dismiss()
                                }
                            } label: {
                                modelRow(option)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(option.catalogAccessibilityDetail ?? "Selects this model")
                        }
                    }
                }
                if normalizedQuery.isEmpty, !unavailableProviders.isEmpty {
                    Section("Saved Providers") {
                        ForEach(unavailableProviders) { provider in
                            Label(unavailableProviderStatus(for: provider), systemImage: "line.3.horizontal.decrease.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if filteredSections.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Choose Model")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, model ID, or capability")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredSections: [ModelPickerSection] {
        guard !normalizedQuery.isEmpty else { return sections }
        return sections.compactMap { section in
            let models = section.models.filter { option in
                let searchable = [
                    option.displayName,
                    option.modelID.rawValue,
                    option.providerName,
                    option.catalogDetailLabel ?? "",
                    option.modelMetadata?.summary ?? "",
                ]
                .joined(separator: " ")
                .lowercased()
                return searchable.contains(normalizedQuery)
            }
            return models.isEmpty ? nil : ModelPickerSection(title: section.title, models: models)
        }
    }

    private func modelRow(_ option: ModelPickerOption) -> some View {
        HStack(spacing: 12) {
            Image(systemName: option.systemImage)
                .frame(width: 24)
                .foregroundStyle(option.providerKind == .openRouter ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(option.displayName)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let detail = option.catalogDetailLabel {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if option.displayName.caseInsensitiveCompare(option.modelID.rawValue) != .orderedSame {
                    Text(option.modelID.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if option.providerID == currentProviderID, option.modelID == currentModelID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(Rectangle())
    }

    private func unavailableProviderStatus(for provider: CloudProviderConfiguration) -> String {
        switch provider.validationStatus {
        case .valid:
            "\(provider.displayName): no curated agent models"
        case .unvalidated:
            "\(provider.displayName): validate key"
        case .invalid:
            "\(provider.displayName): key invalid"
        case .rateLimited:
            "\(provider.displayName): rate limited"
        }
    }
}

private struct ChatThreadRow: View {
    @Environment(\.pinesTheme) private var theme
    let thread: PinesThreadPreview
    let isSelected: Bool

    var body: some View {
        PinesSidebarRow(
            title: thread.title,
            subtitle: "\(thread.lastMessage)\n\(thread.modelName)",
            systemImage: "bubble.left.and.text.bubble.right",
            detail: thread.updatedLabel,
            tint: thread.status.tint(in: theme),
            isSelected: isSelected,
            isActive: thread.status == .streaming
        ) {
            HStack(spacing: theme.spacing.xsmall) {
                if thread.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                        .accessibilityLabel("Pinned")
                }

                PinesStatusIndicator(
                    color: thread.status.tint(in: theme),
                    isActive: thread.status == .streaming,
                    size: 9
                )
            }
        }
    }
}

private extension ModelPickerOption {
    var compactDisplayName: String {
        guard displayName.count > 34 else { return displayName }
        let prefix = String(displayName.prefix(18)).trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(displayName.suffix(12)).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)...\(suffix)"
    }

    var systemImage: String {
        if isLocal {
            return "cpu"
        }
        switch providerKind {
        case .openAI:
            return "sparkles"
        case .anthropic:
            return "brain.head.profile"
        case .gemini:
            return "diamond"
        case .openRouter:
            return "arrow.triangle.branch"
        case .voyageAI:
            return "point.3.connected.trianglepath.dotted"
        case .openAICompatible, .custom, nil:
            return "network"
        }
    }

    var catalogDetailLabel: String? {
        guard providerKind == .openRouter else { return nil }
        var details = [String]()
        if let context = modelMetadata?.contextLength ?? capabilities?.maxContextTokens {
            details.append("\(Self.compactTokenCount(context)) context")
        }
        if let pricing = modelMetadata?.pricing,
           let price = Self.compactTokenPricing(pricing) {
            details.append(price)
        }
        let inputModalities = Set(modelMetadata?.inputModalities ?? [])
        if inputModalities.contains("image") {
            details.append("images")
        }
        if inputModalities.contains("file") || inputModalities.contains("pdf") {
            details.append("files")
        }
        if capabilities?.toolCalling == true {
            details.append("tools")
        }
        if capabilities?.structuredOutputs == true {
            details.append("schema")
        }
        return details.isEmpty ? nil : details.prefix(5).joined(separator: " · ")
    }

    var catalogAccessibilityDetail: String? {
        guard providerKind == .openRouter else { return nil }
        var details = [String]()
        if let catalogDetailLabel {
            details.append(catalogDetailLabel)
        }
        if let summary = modelMetadata?.summary, !summary.isEmpty {
            details.append(summary)
        }
        return details.isEmpty ? nil : details.joined(separator: ". ")
    }

    private static func compactTokenCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            let millions = Double(value) / 1_000_000
            return millions.rounded() == millions ? "\(Int(millions))M" : String(format: "%.1fM", millions)
        }
        if value >= 1_000 {
            let thousands = Double(value) / 1_000
            return thousands.rounded() == thousands ? "\(Int(thousands))K" : String(format: "%.1fK", thousands)
        }
        return value.formatted()
    }

    private static func compactTokenPricing(_ pricing: CloudProviderModelPricing) -> String? {
        guard let prompt = pricing.tokenPricePerMillion(pricing.prompt),
              let completion = pricing.tokenPricePerMillion(pricing.completion)
        else {
            return nil
        }
        return "\(currency(prompt)) in · \(currency(completion)) out / M"
    }

    private static func currency(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let amount = number.doubleValue
        if amount == 0 { return "$0" }
        if amount < 0.01 { return String(format: "$%.4f", amount) }
        if amount < 1 { return String(format: "$%.3f", amount) }
        return String(format: "$%.2f", amount)
    }
}

private struct ChatTranscriptView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var chatState: PinesChatState
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var retrySpin = false
    @State private var editingMessage: ChatMessage?
    @State private var isNearTranscriptBottom = true
    @State private var isAutoScrollPinned = true
    @State private var isComposerFocused = false
    @State private var openSwipeMessageID: UUID?
    @State private var isTranscriptDragging = false
    @State private var lastTranscriptInteractionAt = Date.distantPast
    @State private var firstVisibleMessageThreadID: UUID?
    @State private var firstMessageMeasurementThreadID: UUID?
    @State private var firstMessageInterval: PinesPerformanceInterval?
    @State private var hasMeasuredFirstMessage = false
    let thread: PinesThreadPreview

    private var latestAssistantMessageID: UUID? {
        thread.messages.last(where: { $0.role == .assistant })?.id
    }

    private var activeLiveMessage: PinesLiveChatMessage? {
        guard let activeRunID = chatState.activeRunID else { return nil }
        return chatState.liveMessage(for: activeRunID)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.large) {
                    ChatTranscriptHeader(thread: thread)

                    LazyVStack(spacing: theme.spacing.medium) {
                        ForEach(thread.messages) { message in
                            ChatMessageRow(
                                message: message,
                                liveMessage: chatState.liveMessage(for: message.id),
                                isStreaming: chatState.activeRunID == message.id,
                                showsLocalTokenRate: message.id == latestAssistantMessageID,
                                canEdit: chatState.activeRunID == nil,
                                openSwipeMessageID: $openSwipeMessageID,
                                editingMessage: $editingMessage
                            )
                            .onAppear {
                                firstVisibleMessageThreadID = thread.id
                                finishFirstMessageMeasurement()
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .animation(reduceMotion ? nil : theme.motion.standard, value: thread.messages.count)

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(contentPadding)
                .frame(maxWidth: theme.spacing.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(transcriptDragGesture)
            .pinesExpressiveScrollHaptics()
            .pinesOnScrollNearBottom { isNearBottom in
                isNearTranscriptBottom = isNearBottom
                if isNearBottom {
                    isAutoScrollPinned = true
                } else if !isComposerFocused {
                    isAutoScrollPinned = false
                }
            }
            .overlay(alignment: .bottomTrailing) {
                jumpToLatestButton(proxy: proxy)
                    .padding(.trailing, contentPadding)
                    .padding(.bottom, theme.spacing.small)
            }
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: thread.messages.count) { _, _ in
                guard shouldAutoScrollAfterTranscriptChange else { return }
                if thread.messages.last?.role == .user {
                    isAutoScrollPinned = true
                    scrollToBottom(proxy, animated: chatState.activeRunID == nil)
                } else if isAutoScrollPinned || isNearTranscriptBottom {
                    scrollToBottom(proxy, animated: chatState.activeRunID == nil)
                }
            }
            .onChange(of: chatState.activeRunID) { _, _ in
                if shouldAutoScrollAfterTranscriptChange, isAutoScrollPinned || isNearTranscriptBottom {
                    scrollToBottom(proxy, animated: chatState.activeRunID == nil)
                }
            }
            .background {
                if let activeLiveMessage {
                    LiveChatAutoScrollObserver(liveMessage: activeLiveMessage) {
                        shouldAutoScrollLiveMessage
                    } scroll: {
                        scrollToBottom(proxy, animated: false)
                    }
                }
            }
        }
        .sheet(item: $editingMessage) { message in
            ChatMessageEditSheet(
                message: message,
                cancel: { editingMessage = nil },
                save: { content in
                    editingMessage = nil
                    Task {
                        await appModel.editUserMessage(message, content: content, in: thread.id, services: services)
                    }
                }
            )
        }
        .navigationTitle(thread.title)
        .accessibilityIdentifier("pines.chat.transcript")
        .task(id: thread.id) {
            startFirstMessageMeasurement()
            await appModel.loadThreadMessages(
                threadID: thread.id,
                services: services,
                force: false
            )
            if chatState.threads.first(where: { $0.id == thread.id })?.messages.isEmpty == true {
                finishFirstMessageMeasurement()
            }
        }
        .onDisappear(perform: finishFirstMessageMeasurement)
        .pinesInlineNavigationTitle()
        .toolbar {
            if horizontalSizeClass == .compact {
                ToolbarItem(placement: .principal) {
                    ChatModelSelector(thread: thread, fillWidth: false, maxWidth: 156)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.stopCurrentRun()
                } label: {
                    Image(systemName: "stop.circle")
                }
                .accessibilityLabel("Stop")
                .disabled(chatState.activeRunID == nil)

                Button {
                    haptics.play(.primaryAction)
                    withAnimation(reduceMotion ? nil : theme.motion.emphasized) {
                        retrySpin.toggle()
                    }
                    appModel.retryLastUserMessage(in: thread, services: services)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .pinesRetrySymbolEffect(value: retrySpin)
                }
                .accessibilityLabel("Retry")
                .disabled(chatState.activeRunID != nil || !thread.messages.contains { $0.role == .user })
            }
        }
        .toolbar(tabBarVisibility, for: .tabBar)
        .pinesAppBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: composerInsetSpacing) {
                if let chatError = chatState.chatError {
                    ChatErrorBanner(
                        message: chatError,
                        dismiss: { appModel.dismissChatError() }
                    )
                    .padding(.horizontal, contentPadding)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                ChatComposerBar(threadID: thread.id, isFocused: $isComposerFocused)
                    .padding(.horizontal, contentPadding)
            }
            .padding(.top, composerInsetTopPadding)
            .padding(.bottom, composerInsetBottomPadding)
            .animation(reduceMotion ? nil : theme.motion.standard, value: chatState.chatError)
        }
    }

    private var contentPadding: CGFloat {
        horizontalSizeClass == .compact ? theme.spacing.medium : theme.spacing.large
    }

    private var tabBarVisibility: Visibility {
        horizontalSizeClass == .compact ? .hidden : .automatic
    }

    private var composerInsetSpacing: CGFloat {
        horizontalSizeClass == .compact ? theme.spacing.xsmall : theme.spacing.small
    }

    private var composerInsetTopPadding: CGFloat {
        horizontalSizeClass == .compact ? theme.spacing.xxsmall : theme.spacing.xsmall
    }

    private var composerInsetBottomPadding: CGFloat {
        guard horizontalSizeClass == .compact else { return theme.spacing.small }
        return isComposerFocused ? theme.spacing.xxsmall : theme.spacing.xsmall
    }

    @ViewBuilder
    private func jumpToLatestButton(proxy: ScrollViewProxy) -> some View {
        if !isAutoScrollPinned {
            Button {
                haptics.play(.navigationSelected)
                isAutoScrollPinned = true
                scrollToBottom(proxy, animated: true)
            } label: {
                Image(systemName: "arrow.down")
            }
            .accessibilityLabel("Jump to latest message")
            .pinesButtonStyle(.icon)
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
        }
    }

    private var transcriptDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { _ in
                guard !isTranscriptDragging else { return }
                isTranscriptDragging = true
                lastTranscriptInteractionAt = Date()
                if chatState.activeRunID != nil, !isNearTranscriptBottom, isAutoScrollPinned {
                    isAutoScrollPinned = false
                }
                guard isComposerFocused else { return }
                isComposerFocused = false
            }
            .onEnded { _ in
                lastTranscriptInteractionAt = Date()
                isTranscriptDragging = false
            }
    }

    private var shouldAutoScrollAfterTranscriptChange: Bool {
        !isTranscriptDragging && Date().timeIntervalSince(lastTranscriptInteractionAt) > 0.35
    }

    private var shouldAutoScrollLiveMessage: Bool {
        shouldAutoScrollAfterTranscriptChange && (isAutoScrollPinned || isNearTranscriptBottom)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let shouldAnimate = animated && shouldAutoScrollAfterTranscriptChange && !reduceMotion
        if shouldAnimate {
            withAnimation(theme.motion.standard) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
    }

    @MainActor
    private func startFirstMessageMeasurement() {
        if firstMessageMeasurementThreadID != thread.id {
            if let firstMessageInterval {
                services.runtimeMetrics.end(firstMessageInterval)
            }
            firstMessageInterval = nil
            firstMessageMeasurementThreadID = thread.id
            hasMeasuredFirstMessage = false
        }
        guard !hasMeasuredFirstMessage, firstMessageInterval == nil else { return }
        firstMessageInterval = services.runtimeMetrics.begin(.threadToFirstMessage)
        if firstVisibleMessageThreadID == thread.id {
            finishFirstMessageMeasurement()
        }
    }

    @MainActor
    private func finishFirstMessageMeasurement() {
        guard let interval = firstMessageInterval else { return }
        firstMessageInterval = nil
        hasMeasuredFirstMessage = true
        services.runtimeMetrics.end(interval)
    }

}

private extension View {
    @ViewBuilder
    func pinesRetrySymbolEffect(value: Bool) -> some View {
        if #available(iOS 18.0, *) {
            symbolEffect(.rotate, options: .nonRepeating, value: value)
        } else {
            self
        }
    }
}

private extension View {
    @ViewBuilder
    func pinesOnScrollNearBottom(_ action: @escaping (Bool) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            modifier(ChatNearBottomObserver(action: action))
        } else {
            self
        }
    }
}

@available(iOS 18.0, *)
private struct ChatNearBottomObserver: ViewModifier {
    let action: (Bool) -> Void

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: Bool.self) { geometry in
            Self.isNearBottom(geometry)
        } action: { _, isNearBottom in
            action(isNearBottom)
        }
    }

    private static func isNearBottom(_ geometry: ScrollGeometry) -> Bool {
        let minOffset = -geometry.contentInsets.top
        let maxOffset = geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom
        let hasScrollableContent = maxOffset > minOffset + 6
        guard hasScrollableContent else {
            return true
        }
        return geometry.contentOffset.y >= maxOffset - 96
    }
}

private struct LiveChatAutoScrollObserver: View {
    @ObservedObject var liveMessage: PinesLiveChatMessage
    let shouldScroll: () -> Bool
    let scroll: () -> Void
    @State private var lastScrollAt = Date.distantPast

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: liveMessage.snapshot) { _, _ in
                guard shouldScroll() else { return }
                let now = Date()
                guard now.timeIntervalSince(lastScrollAt) >= 0.12 else { return }
                lastScrollAt = now
                scroll()
            }
    }
}

private struct ChatMessageRow: View {
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    let message: ChatMessage
    let liveMessage: PinesLiveChatMessage?
    let isStreaming: Bool
    let showsLocalTokenRate: Bool
    let canEdit: Bool
    @Binding var openSwipeMessageID: UUID?
    @Binding var editingMessage: ChatMessage?

    var body: some View {
        if let liveMessage {
            LiveChatMessageRowContent(
                baseMessage: message,
                liveMessage: liveMessage,
                isStreaming: isStreaming,
                showsLocalTokenRate: showsLocalTokenRate,
                canEdit: canEdit,
                openSwipeMessageID: $openSwipeMessageID,
                copyMessage: copyMessage,
                editMessage: editMessage,
                addAttachmentsToVault: addAttachmentsToVault
            )
        } else {
            ChatMessageRowContent(
                message: message,
                isStreaming: isStreaming,
                showsLocalTokenRate: showsLocalTokenRate,
                canEdit: canEdit && message.role == .user,
                canAddAttachmentsToVault: !message.attachments.isEmpty,
                openSwipeMessageID: $openSwipeMessageID,
                copyMessage: { copyMessage(message) },
                editMessage: editMessage,
                addAttachmentsToVault: addAttachmentsToVault
            )
        }
    }

    private func copyMessage(_ message: ChatMessage) {
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty {
            let text = message.role == .assistant
                ? MarkdownMessageParser().plainText(from: content)
                : content
            copyToPasteboard(text)
        } else {
            copyToPasteboard(message.attachments.map(\.fileName).joined(separator: "\n"))
        }
        haptics.play(.primaryAction)
    }

    private func addAttachmentsToVault() {
        Task {
            await appModel.addMessageAttachmentsToVault(message, services: services)
        }
    }

    private func editMessage() {
        editingMessage = message
    }
}

private struct LiveChatMessageRowContent: View {
    @ObservedObject var liveMessage: PinesLiveChatMessage
    let baseMessage: ChatMessage
    let isStreaming: Bool
    let showsLocalTokenRate: Bool
    let canEdit: Bool
    @Binding var openSwipeMessageID: UUID?
    let copyMessage: (ChatMessage) -> Void
    let editMessage: () -> Void
    let addAttachmentsToVault: () -> Void

    init(
        baseMessage: ChatMessage,
        liveMessage: PinesLiveChatMessage,
        isStreaming: Bool,
        showsLocalTokenRate: Bool,
        canEdit: Bool,
        openSwipeMessageID: Binding<UUID?>,
        copyMessage: @escaping (ChatMessage) -> Void,
        editMessage: @escaping () -> Void,
        addAttachmentsToVault: @escaping () -> Void
    ) {
        self.liveMessage = liveMessage
        self.baseMessage = baseMessage
        self.isStreaming = isStreaming
        self.showsLocalTokenRate = showsLocalTokenRate
        self.canEdit = canEdit
        _openSwipeMessageID = openSwipeMessageID
        self.copyMessage = copyMessage
        self.editMessage = editMessage
        self.addAttachmentsToVault = addAttachmentsToVault
    }

    var body: some View {
        let message = liveMessage.snapshot.merged(into: baseMessage)
        ChatMessageRowContent(
            message: message,
            isStreaming: isStreaming,
            showsLocalTokenRate: showsLocalTokenRate,
            canEdit: canEdit && message.role == .user,
            canAddAttachmentsToVault: !message.attachments.isEmpty,
            openSwipeMessageID: $openSwipeMessageID,
            copyMessage: { copyMessage(message) },
            editMessage: editMessage,
            addAttachmentsToVault: addAttachmentsToVault
        )
    }
}

private struct ChatMessageRowContent: View {
    @Environment(\.pinesTheme) private var theme
    let message: ChatMessage
    let isStreaming: Bool
    let showsLocalTokenRate: Bool
    let canEdit: Bool
    let canAddAttachmentsToVault: Bool
    @Binding var openSwipeMessageID: UUID?
    let copyMessage: () -> Void
    let editMessage: () -> Void
    let addAttachmentsToVault: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
            ChatBubble(
                message: message,
                isStreaming: isStreaming,
                canEdit: canEdit,
                canAddAttachmentsToVault: canAddAttachmentsToVault,
                openSwipeMessageID: $openSwipeMessageID,
                copyMessage: copyMessage,
                editMessage: editMessage,
                addAttachmentsToVault: addAttachmentsToVault
            )
            .accessibilityIdentifier("pines.chat.message.\(message.role.rawValue)")

            if showsLocalTokenRate,
               let performance = ChatLocalTokenRateSummary(metadata: message.providerMetadata) {
                ChatLocalTokenRateView(performance: performance)
                    .padding(.leading, theme.spacing.small)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct ChatTranscriptHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    let thread: PinesThreadPreview

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            if horizontalSizeClass != .compact {
                ChatModelSelector(thread: thread, fillWidth: false, maxWidth: 280)
            }

            Text("Approx. \(thread.tokenCount) tokens - \(thread.status.title)")
                .font(theme.typography.callout)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatModelSelector: View {
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    let thread: PinesThreadPreview
    var fillWidth: Bool
    var maxWidth: CGFloat?

    var body: some View {
        ChatModelPickerButton(
            currentProviderID: thread.providerID,
            currentModelID: thread.modelID,
            fallbackLabel: thread.modelName,
            accessibilityLabel: "Chat model",
            fillWidth: fillWidth,
            maxWidth: maxWidth
        ) { option in
            await appModel.selectModel(option, for: thread.id, services: services)
        }
    }
}

private struct ChatBubble: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var webSearchCitations: [WebSearchCitation] = []
    @State private var citationRevision: UInt64 = 0
    let message: ChatMessage
    let isStreaming: Bool
    let canEdit: Bool
    let canAddAttachmentsToVault: Bool
    @Binding var openSwipeMessageID: UUID?
    let copyMessage: () -> Void
    let editMessage: () -> Void
    let addAttachmentsToVault: () -> Void

    var body: some View {
        SwipeableChatBubble(
            id: message.id,
            leadingActions: leadingSwipeActions,
            trailingActions: trailingSwipeActions,
            openBubbleID: $openSwipeMessageID
        ) {
            bubbleContent
        }
        .task(id: WebCitationDecodeTaskID(messageID: message.id, revision: citationRevision)) {
            webSearchCitations = await PinesChatMetadataCache.shared.webSearchCitations(rawJSON: webCitationJSON)
        }
        .onChange(of: webCitationJSON) { _, _ in
            citationRevision &+= 1
        }
    }

    private var bubbleContent: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous)
        return VStack(alignment: .leading, spacing: theme.spacing.small) {
                HStack(spacing: theme.spacing.xsmall) {
                    PinesStatusIndicator(
                        color: message.role.tint(in: theme),
                        isActive: isStreaming,
                        size: isStreaming ? 9 : 8
                    )

                    Text(message.role.title)
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                        .pinesFittingText()

                    Spacer(minLength: theme.spacing.small)

                    if isStreaming {
                        Text("streaming")
                            .font(theme.typography.caption.weight(.medium))
                            .foregroundStyle(theme.colors.accent)
                            .pinesFittingText()
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }

                if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MarkdownMessageView(
                        messageID: message.id,
                        content: message.content,
                        isStreaming: isStreaming
                    )
                }

                if !message.attachments.isEmpty {
                    ChatAttachmentList(attachments: message.attachments)
                }

                if !webSearchCitations.isEmpty {
                    ChatWebSearchCitationList(citations: webSearchCitations)
                }
                let providerCitations = message.providerMetadata.providerCitations
                if !providerCitations.isEmpty {
                    ChatProviderCitationList(citations: providerCitations)
                }
                if let searchSuggestionsHTML = ChatWebSearchSuggestionsView.html(from: message.providerMetadata) {
                    ChatWebSearchSuggestionsView(html: searchSuggestionsHTML)
                }
                let hostedToolEntries = message.providerMetadata.hostedToolAuditEntries
                if !hostedToolEntries.isEmpty {
                    ChatHostedToolTimeline(entries: hostedToolEntries)
                }
                if let provenance = OpenRouterRunProvenance(metadata: message.providerMetadata) {
                    ChatOpenRouterReceiptView(provenance: provenance)
                }

                let agentActivities = PinesAppModel.agentActivities(from: message.providerMetadata)
                if !agentActivities.isEmpty {
                    ChatAgentActivityList(activities: agentActivities)
                } else if !message.toolCalls.isEmpty {
                    ChatToolCallList(toolCalls: message.toolCalls)
                }

                if message.role == .assistant,
                   let receipt = ChatContextReceipt(metadata: message.providerMetadata) {
                    ChatContextReceiptView(receipt: receipt)
                }
            }
            .padding(theme.spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(message.role.bubbleFill(in: theme), in: shape)
            .overlay {
                shape
                    .strokeBorder(message.role.bubbleBorder(in: theme), lineWidth: theme.stroke.hairline)
            }
            .shadow(color: theme.shadow.panelColor.opacity(message.role == .assistant ? 0.55 : 0.32), radius: theme.shadow.panelRadius * 0.25, x: 0, y: theme.shadow.panelY * 0.20)
            .scaleEffect(isStreaming && !reduceMotion ? 1.006 : 1)
            .animation(reduceMotion ? nil : theme.motion.fast, value: isStreaming)
            .accessibilityElement(children: .contain)
            .contextMenu {
                Button {
                    haptics.play(.primaryAction)
                    copyToPasteboard(message.content)
                } label: {
                    Label("Copy as Markdown", systemImage: "doc.on.doc")
                }

                Button {
                    haptics.play(.primaryAction)
                    copyToPasteboard(MarkdownMessageParser().plainText(from: message.content))
                } label: {
                    Label("Copy as Plain Text", systemImage: "text.alignleft")
                }
            }
    }

    private var webCitationJSON: String {
        message.providerMetadata[CloudProviderMetadataKeys.webSearchCitationsJSON] ?? ""
    }

    private var leadingSwipeActions: [ChatBubbleSwipeAction] {
        guard canAddAttachmentsToVault else { return [] }
        return [
            ChatBubbleSwipeAction(
                id: "vault",
                title: "Vault",
                systemImage: "tray.and.arrow.down",
                tint: theme.colors.accent,
                perform: addAttachmentsToVault
            ),
        ]
    }

    private var trailingSwipeActions: [ChatBubbleSwipeAction] {
        var actions = [
            ChatBubbleSwipeAction(
                id: "copy",
                title: "Copy",
                systemImage: "doc.on.doc",
                tint: theme.colors.info,
                perform: copyMessage
            ),
        ]
        if canEdit {
            actions.append(
                ChatBubbleSwipeAction(
                    id: "edit",
                    title: "Edit",
                    systemImage: "square.and.pencil",
                    tint: theme.colors.accent,
                    perform: editMessage
                )
            )
        }
        return actions
    }
}

private struct ChatContextReceipt: Hashable {
    let inputTokens: Int
    let inputBudget: Int
    let contextWindow: Int
    let reservedCompletion: Int
    let originalMessages: Int
    let includedMessages: Int
    let droppedMessages: Int
    let clippedMessages: Int
    let lineageOriginalMessages: Int
    let lineageIncludedMessages: Int
    let lineageDroppedMessages: Int
    let lineageClippedMessages: Int
    let lineageTranscriptDroppedMessages: Int
    let evidenceCount: Int
    let evidenceSources: [String]
    let budgetSource: String

    init?(metadata: [String: String]) {
        guard let estimated = metadata[ChatContextMetadataKeys.estimatedInputTokens].flatMap(Int.init),
              let inputBudget = metadata[ChatContextMetadataKeys.inputBudgetTokens].flatMap(Int.init),
              let contextWindow = metadata[ChatContextMetadataKeys.contextWindowTokens].flatMap(Int.init)
        else { return nil }
        inputTokens = metadata[ChatContextMetadataKeys.exactInputTokens].flatMap(Int.init) ?? estimated
        self.inputBudget = inputBudget
        self.contextWindow = contextWindow
        reservedCompletion = metadata[ChatContextMetadataKeys.reservedCompletionTokens].flatMap(Int.init) ?? 0
        originalMessages = metadata[ChatContextMetadataKeys.originalMessageCount].flatMap(Int.init) ?? 0
        includedMessages = metadata[ChatContextMetadataKeys.includedMessageCount].flatMap(Int.init) ?? 0
        droppedMessages = metadata[ChatContextMetadataKeys.droppedMessageCount].flatMap(Int.init) ?? 0
        clippedMessages = metadata[ChatContextMetadataKeys.clippedMessageCount].flatMap(Int.init) ?? 0
        lineageOriginalMessages = metadata[ChatContextMetadataKeys.lineageOriginalMessageCount].flatMap(Int.init) ?? originalMessages
        lineageIncludedMessages = metadata[ChatContextMetadataKeys.lineageIncludedMessageCount].flatMap(Int.init) ?? includedMessages
        lineageDroppedMessages = metadata[ChatContextMetadataKeys.lineageDroppedMessageCount].flatMap(Int.init) ?? droppedMessages
        lineageClippedMessages = metadata[ChatContextMetadataKeys.lineageClippedMessageCount].flatMap(Int.init) ?? clippedMessages
        lineageTranscriptDroppedMessages = metadata[ChatContextMetadataKeys.lineageTranscriptDroppedMessageCount].flatMap(Int.init) ?? 0
        evidenceCount = metadata[ChatContextMetadataKeys.lineageEvidenceCount].flatMap(Int.init)
            ?? metadata[ChatContextEvidenceMetadataKeys.evidenceCount].flatMap(Int.init)
            ?? 0
        evidenceSources = (
            metadata[ChatContextMetadataKeys.lineageEvidenceSources]
                ?? metadata[ChatContextEvidenceMetadataKeys.evidenceSources]
                ?? ""
        )
            .split(separator: ",")
            .map(String.init)
        budgetSource = metadata[ChatContextMetadataKeys.budgetSource] ?? "unknown"
    }

    var reduced: Bool {
        droppedMessages > 0
            || clippedMessages > 0
            || lineageDroppedMessages > 0
            || lineageClippedMessages > 0
            || lineageTranscriptDroppedMessages > 0
    }
}

private struct ChatContextReceiptView: View {
    @Environment(\.pinesTheme) private var theme
    let receipt: ChatContextReceipt

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                LabeledContent("Model window", value: "\(receipt.contextWindow.formatted()) tokens")
                LabeledContent("Completion reserve", value: "\(receipt.reservedCompletion.formatted()) tokens")
                LabeledContent("Final-step messages", value: "\(receipt.includedMessages) of \(receipt.originalMessages)")
                if receipt.lineageOriginalMessages != receipt.originalMessages
                    || receipt.lineageIncludedMessages != receipt.includedMessages {
                    LabeledContent(
                        "Initial transcript assembly",
                        value: "\(receipt.lineageIncludedMessages) of \(receipt.lineageOriginalMessages)"
                    )
                }
                if receipt.droppedMessages > 0 {
                    LabeledContent("Summarized or omitted", value: "\(receipt.droppedMessages)")
                }
                if receipt.clippedMessages > 0 {
                    LabeledContent("Clipped", value: "\(receipt.clippedMessages)")
                }
                if receipt.lineageDroppedMessages > 0 || receipt.lineageClippedMessages > 0 {
                    LabeledContent(
                        "Initial context reduced",
                        value: "\(receipt.lineageDroppedMessages) omitted, \(receipt.lineageClippedMessages) clipped"
                    )
                }
                if receipt.lineageTranscriptDroppedMessages > 0 {
                    LabeledContent("Invalid or interrupted rows removed", value: "\(receipt.lineageTranscriptDroppedMessages)")
                }
                if receipt.evidenceCount > 0 {
                    LabeledContent("Reference sources", value: receipt.evidenceSources.isEmpty ? "\(receipt.evidenceCount)" : receipt.evidenceSources.joined(separator: ", "))
                }
                if receipt.budgetSource == "conservative-default" {
                    Text("The provider did not report a context window, so Pines used a conservative 4,096-token fallback.")
                        .foregroundStyle(theme.colors.tertiaryText)
                }
            }
            .font(theme.typography.caption)
            .foregroundStyle(theme.colors.secondaryText)
            .padding(.top, theme.spacing.xxsmall)
        } label: {
            Label(
                "Context \(receipt.inputTokens.formatted()) / \(receipt.inputBudget.formatted())",
                systemImage: receipt.reduced ? "text.badge.minus" : "checkmark.circle"
            )
            .font(theme.typography.caption.weight(.semibold))
            .foregroundStyle(receipt.reduced ? theme.colors.warning : theme.colors.secondaryText)
        }
        .accessibilityLabel("Context receipt, \(receipt.inputTokens) of \(receipt.inputBudget) input tokens")
    }
}

private struct ChatLocalTokenRateSummary: Hashable {
    let tokensPerSecond: Double

    init?(metadata: [String: String]) {
        guard let rawValue = metadata[LocalProviderMetadataKeys.generationTokensPerSecond],
              let tokensPerSecond = Double(rawValue),
              tokensPerSecond.isFinite,
              tokensPerSecond > 0
        else { return nil }
        self.tokensPerSecond = tokensPerSecond
    }

    var displayValue: String {
        let format = tokensPerSecond >= 100 ? "%.0f" : "%.1f"
        return String(format: format, tokensPerSecond)
    }
}

private struct ChatLocalTokenRateView: View {
    @Environment(\.pinesTheme) private var theme
    let performance: ChatLocalTokenRateSummary

    var body: some View {
        HStack(spacing: theme.spacing.xxsmall) {
            Image(systemName: "speedometer")
                .font(theme.typography.caption.weight(.semibold))
                .frame(width: 14, height: 14)

            Text("\(performance.displayValue) Token/s")
                .font(theme.typography.caption.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(theme.colors.secondaryText)
        .accessibilityLabel("\(performance.displayValue) tokens per second")
    }
}

#if canImport(WebKit) && canImport(UIKit)
private struct ChatWebSearchSuggestionsView: View {
    @Environment(\.pinesTheme) private var theme
    let html: String

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            Text("Google Search suggestions")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
            SearchSuggestionsWebView(html: html)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
        }
        .padding(.vertical, theme.spacing.xsmall)
        .padding(.horizontal, theme.spacing.small)
        .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)
        }
    }

    static func html(from metadata: [String: String]) -> String? {
        let html = metadata[CloudProviderMetadataKeys.webSearchSuggestionsHTML]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (html ?? "").isEmpty ? nil : html
    }
}

private struct SearchSuggestionsWebView: UIViewRepresentable {
    let html: String

    final class Coordinator {
        var loadedHTML: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context _: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }
}
#else
private struct ChatWebSearchSuggestionsView: View {
    let html: String

    var body: some View {
        EmptyView()
    }

    static func html(from metadata: [String: String]) -> String? {
        let html = metadata[CloudProviderMetadataKeys.webSearchSuggestionsHTML]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (html ?? "").isEmpty ? nil : html
    }
}
#endif

private struct ChatWebSearchCitationList: View {
    @Environment(\.pinesTheme) private var theme
    let citations: [WebSearchCitation]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            HStack(spacing: theme.spacing.xsmall) {
                Image(systemName: "globe")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 16, height: 16)
                Text("Web sources")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
            }

            ForEach(citations.prefix(6)) { citation in
                if let url = URL(string: citation.url) {
                    Link(destination: url) {
                        HStack(spacing: theme.spacing.xxsmall) {
                            Text(citation.source)
                                .font(theme.typography.caption.weight(.semibold))
                                .foregroundStyle(theme.colors.secondaryText)
                                .lineLimit(1)

                            Text(citation.title)
                                .font(theme.typography.caption.weight(.medium))
                                .foregroundStyle(theme.colors.accent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.vertical, theme.spacing.xsmall)
        .padding(.horizontal, theme.spacing.small)
        .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)
        }
        .accessibilityLabel("\(citations.count) web search sources")
    }

    nonisolated static func citations(from raw: String) -> [WebSearchCitation] {
        guard let data = raw.data(using: .utf8),
              let citations = try? JSONDecoder().decode([WebSearchCitation].self, from: data)
        else { return [] }
        return citations
    }
}

private struct WebCitationDecodeTaskID: Hashable {
    let messageID: UUID
    let revision: UInt64
}

actor PinesChatMetadataCache {
    static let shared = PinesChatMetadataCache()

    private final class Box: NSObject {
        let citations: [WebSearchCitation]

        init(_ citations: [WebSearchCitation]) {
            self.citations = citations
        }
    }

    private let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 256
        cache.totalCostLimit = 4 * 1_024 * 1_024
        return cache
    }()

    func webSearchCitations(rawJSON: String) -> [WebSearchCitation] {
        guard !rawJSON.isEmpty else { return [] }
        let key = rawJSON as NSString
        if let cached = cache.object(forKey: key) {
            return cached.citations
        }
        let citations = ChatWebSearchCitationList.citations(from: rawJSON)
        cache.setObject(Box(citations), forKey: key, cost: max(1, rawJSON.utf8.count))
        return citations
    }

    func purge() {
        cache.removeAllObjects()
    }
}

private struct ChatProviderCitationList: View {
    @Environment(\.pinesTheme) private var theme
    let citations: [ProviderCitation]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            HStack(spacing: theme.spacing.xsmall) {
                Image(systemName: "quote.bubble")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 16, height: 16)
                Text("Provider sources")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
            }

            ForEach(citations.prefix(6)) { citation in
                HStack(spacing: theme.spacing.xxsmall) {
                    Text(citation.sourceType.title)
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)

                    if let url = citation.url, let link = URL(string: url) {
                        Link(citation.title ?? url, destination: link)
                            .font(theme.typography.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(citation.providerSourceTitle)
                            .font(theme.typography.caption.weight(.medium))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, theme.spacing.xsmall)
        .padding(.horizontal, theme.spacing.small)
        .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)
        }
        .accessibilityLabel("\(citations.count) provider sources")
    }
}

private extension ProviderCitation {
    var providerSourceTitle: String {
        var parts = [String]()
        if let title, !title.isEmpty {
            parts.append(title)
        }
        if let fileID, !fileID.isEmpty {
            parts.append(fileID)
        }
        if let page {
            parts.append("p. \(page)")
        }
        if let citedText, !citedText.isEmpty {
            parts.append(citedText)
        }
        return parts.first ?? source ?? "Source"
    }
}

private extension ProviderCitationSourceType {
    var title: String {
        switch self {
        case .web:
            "Web"
        case .file:
            "File"
        case .pdf:
            "PDF"
        case .text:
            "Text"
        case .searchResult:
            "Search"
        case .vaultChunk:
            "Vault"
        case .unknown:
            "Source"
        }
    }
}

private struct ChatHostedToolTimeline: View {
    @Environment(\.pinesTheme) private var theme
    let entries: [HostedToolAuditEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            HStack(spacing: theme.spacing.xsmall) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.warning)
                    .frame(width: 16, height: 16)
                Text("Hosted tool timeline")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
            }

            ForEach(entries.prefix(6)) { entry in
                HStack(alignment: .top, spacing: theme.spacing.xsmall) {
                    Image(systemName: entry.kind.chatSystemImage)
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(entry.requiresApproval ? theme.colors.warning : theme.colors.accent)
                        .frame(width: 16, height: 16)

                    VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                        HStack(spacing: theme.spacing.xxsmall) {
                            Text(entry.chatTitle)
                                .font(theme.typography.caption.weight(.semibold))
                                .foregroundStyle(theme.colors.primaryText)
                                .lineLimit(1)

                            if let status = entry.status {
                                Text(status.chatTitle)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(theme.colors.secondaryText)
                                    .lineLimit(1)
                            }
                        }

                        Text(entry.chatDetail)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, theme.spacing.xsmall)
                .padding(.horizontal, theme.spacing.small)
                .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                        .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)
                }
            }
        }
        .accessibilityLabel("\(entries.count) provider-hosted tool events")
    }
}

private extension HostedToolAuditEntry {
    var chatTitle: String {
        if let name, !name.isEmpty {
            return name
        }
        if let serverLabel, !serverLabel.isEmpty {
            return serverLabel
        }
        return kind.chatTitle
    }

    var chatDetail: String {
        var parts = ["Provider-hosted \(type.replacingOccurrences(of: "_", with: " "))"]
        if let serverURL, !serverURL.isEmpty {
            parts.append(serverURL)
        }
        if let containerID, !containerID.isEmpty {
            parts.append("container \(containerID)")
        }
        if requiresAgentExecution {
            parts.append("agent context")
        }
        if requiresApproval {
            parts.append("approval required")
        }
        return parts.joined(separator: " - ")
    }
}

private extension OpenAIHostedToolKind {
    var chatTitle: String {
        switch self {
        case .webSearch:
            "Web search"
        case .webFetch:
            "Web fetch"
        case .fileSearch:
            "File search"
        case .computerUse:
            "Computer use"
        case .codeInterpreter:
            "Code execution"
        case .imageGeneration:
            "Image generation"
        case .mcp:
            "Remote MCP"
        case .textEditor:
            "Text editor"
        case .bash:
            "Bash"
        case .toolSearch:
            "Tool search"
        case .custom:
            "Hosted tool"
        }
    }

    var chatSystemImage: String {
        switch self {
        case .webSearch:
            "globe"
        case .webFetch:
            "link"
        case .fileSearch:
            "doc.text.magnifyingglass"
        case .computerUse:
            "display"
        case .codeInterpreter:
            "terminal"
        case .imageGeneration:
            "photo"
        case .mcp:
            "network"
        case .textEditor:
            "doc.text"
        case .bash:
            "terminal"
        case .toolSearch:
            "magnifyingglass"
        case .custom:
            "wrench.and.screwdriver"
        }
    }
}

private extension OpenAIHostedToolCallStatus {
    var chatTitle: String {
        switch self {
        case .queued:
            "queued"
        case .inProgress:
            "running"
        case .completed:
            "complete"
        case .failed:
            "failed"
        case .cancelled:
            "cancelled"
        case .requiresAction:
            "needs approval"
        }
    }
}

private struct ChatAgentActivityList: View {
    @Environment(\.pinesTheme) private var theme
    let activities: [AgentActivityEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            ForEach(activities) { activity in
                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    HStack(alignment: .top, spacing: theme.spacing.xsmall) {
                        Image(systemName: activity.status.systemImage)
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(activity.status.tint(in: theme))
                            .frame(width: 18, height: 18)
                            .symbolEffect(.pulse, options: .repeating, value: activity.status == .running)

                        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                            Text(activity.title)
                                .font(theme.typography.caption.weight(.semibold))
                                .foregroundStyle(theme.colors.primaryText)
                                .lineLimit(1)

                            Text(activity.detail)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }

                    if !activity.links.isEmpty {
                        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                            ForEach(activity.links.prefix(4)) { link in
                                AgentActivityLinkRow(link: link)
                            }
                        }
                        .padding(.leading, 18 + theme.spacing.xsmall)
                    }
                }
                .padding(.vertical, theme.spacing.xsmall)
                .padding(.horizontal, theme.spacing.small)
                .background(theme.colors.controlFill.opacity(activity.status.backgroundOpacity), in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                        .strokeBorder(activity.status.tint(in: theme).opacity(activity.status.borderOpacity), lineWidth: theme.stroke.hairline)
                }
            }
        }
        .accessibilityLabel("\(activities.count) agent activities")
    }
}

private struct AgentActivityLinkRow: View {
    @Environment(\.pinesTheme) private var theme
    let link: AgentActivityLink

    var body: some View {
        Group {
            if let url = URL(string: link.url) {
                Link(destination: url) {
                    rowLabel
                }
            }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: theme.spacing.xxsmall) {
            Image(systemName: "link")
                .font(theme.typography.caption)
            Text(link.title)
                .font(theme.typography.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(theme.colors.accent)
    }
}

private struct ChatToolCallList: View {
    @Environment(\.pinesTheme) private var theme
    let toolCalls: [ToolCallDelta]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            ForEach(toolCalls, id: \.id) { toolCall in
                HStack(alignment: .top, spacing: theme.spacing.xsmall) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.accent)
                        .frame(width: 16, height: 16)

                    VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                        Text(toolCall.name)
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)

                        if let preview = argumentsPreview(for: toolCall) {
                            Text(preview)
                                .font(theme.typography.code)
                                .foregroundStyle(theme.colors.secondaryText)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, theme.spacing.xsmall)
                .padding(.horizontal, theme.spacing.small)
                .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                        .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)
                }
            }
        }
        .accessibilityLabel("\(toolCalls.count) tool calls")
    }

    private func argumentsPreview(for toolCall: ToolCallDelta) -> String? {
        let trimmed = toolCall.argumentsFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed != "{}" else { return nil }
        let collapsed = trimmed
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return collapsed.count > 220 ? "\(collapsed.prefix(220))..." : collapsed
    }
}

private struct ChatBubbleSwipeAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let perform: () -> Void
}

private extension AgentActivityStatus {
    var systemImage: String {
        switch self {
        case .waitingForApproval:
            "hand.raised"
        case .running:
            "arrow.triangle.2.circlepath"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .denied:
            "xmark.circle.fill"
        }
    }

    var backgroundOpacity: Double {
        switch self {
        case .running, .waitingForApproval:
            0.92
        case .completed:
            0.72
        case .failed, .denied:
            0.84
        }
    }

    var borderOpacity: Double {
        switch self {
        case .running:
            0.42
        case .waitingForApproval:
            0.34
        case .completed:
            0.22
        case .failed, .denied:
            0.46
        }
    }

    func tint(in theme: PinesTheme) -> Color {
        switch self {
        case .waitingForApproval:
            theme.colors.warning
        case .running:
            theme.colors.accent
        case .completed:
            theme.colors.success
        case .failed, .denied:
            theme.colors.danger
        }
    }
}

private struct SwipeableChatBubble<Content: View>: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: UUID
    let leadingActions: [ChatBubbleSwipeAction]
    let trailingActions: [ChatBubbleSwipeAction]
    @Binding var openBubbleID: UUID?
    @ViewBuilder let content: () -> Content
    @GestureState private var dragOffset: CGFloat = 0
    @State private var settledOffset: CGFloat = 0

    private let actionButtonWidth: CGFloat = 72
    private let actionButtonSpacing: CGFloat = 10
    private let actionRevealGap: CGFloat = 18

    var body: some View {
        ZStack {
            actionRail
                .opacity(revealedOffset == 0 ? 0 : 1)

            content()
                .offset(x: revealedOffset)
                .simultaneousGesture(horizontalSwipeGesture)
                .animation(reduceMotion ? nil : theme.motion.fast, value: settledOffset)
        }
        .onChange(of: leadingActions.count) { _, _ in closeActions() }
        .onChange(of: trailingActions.count) { _, _ in closeActions() }
        .onChange(of: openBubbleID) { _, newValue in
            guard newValue != id, settledOffset != 0 else { return }
            closeActions(clearOpenBubble: false)
        }
        .onDisappear {
            if openBubbleID == id {
                openBubbleID = nil
            }
        }
    }

    private var actionRail: some View {
        HStack(spacing: 0) {
            HStack(spacing: actionButtonSpacing) {
                ForEach(leadingActions) { action in
                    ChatBubbleSwipeActionButton(action: action, width: actionButtonWidth) {
                        closeActions()
                    }
                }
            }

            Spacer(minLength: theme.spacing.small)

            HStack(spacing: actionButtonSpacing) {
                ForEach(trailingActions) { action in
                    ChatBubbleSwipeActionButton(action: action, width: actionButtonWidth) {
                        closeActions()
                    }
                }
            }
        }
        .padding(.horizontal, actionRevealGap / 2)
        .frame(maxWidth: .infinity)
    }

    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .updating($dragOffset) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                settle(after: value)
            }
    }

    private var revealedOffset: CGFloat {
        clamp(settledOffset + dragOffset)
    }

    private var leadingRevealWidth: CGFloat {
        actionRevealWidth(for: leadingActions.count)
    }

    private var trailingRevealWidth: CGFloat {
        actionRevealWidth(for: trailingActions.count)
    }

    private func settle(after value: DragGesture.Value) {
        let projected = clamp(settledOffset + value.predictedEndTranslation.width * 0.45)
        let current = clamp(settledOffset + value.translation.width)
        let target = abs(projected) > abs(current) ? projected : current
        let threshold: CGFloat = 42

        withAnimation(reduceMotion ? nil : theme.motion.fast) {
            if target > threshold, leadingRevealWidth > 0 {
                settledOffset = leadingRevealWidth
                openBubbleID = id
            } else if target < -threshold, trailingRevealWidth > 0 {
                settledOffset = -trailingRevealWidth
                openBubbleID = id
            } else {
                settledOffset = 0
                if openBubbleID == id {
                    openBubbleID = nil
                }
            }
        }
    }

    private func closeActions(clearOpenBubble: Bool = true) {
        withAnimation(reduceMotion ? nil : theme.motion.fast) {
            settledOffset = 0
            if clearOpenBubble, openBubbleID == id {
                openBubbleID = nil
            }
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, -trailingRevealWidth), leadingRevealWidth)
    }

    private func actionRevealWidth(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * actionButtonWidth
            + CGFloat(count - 1) * actionButtonSpacing
            + actionRevealGap
    }
}

private struct ChatBubbleSwipeActionButton: View {
    @Environment(\.pinesTheme) private var theme
    let action: ChatBubbleSwipeAction
    let width: CGFloat
    let closeActions: () -> Void

    var body: some View {
        Button {
            closeActions()
            action.perform()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(height: 18)

                Text(action.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(action.tint)
            .frame(width: width)
            .frame(minHeight: 58)
            .background(action.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                    .strokeBorder(action.tint.opacity(0.18), lineWidth: theme.stroke.hairline)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
    }
}

private struct ChatMessageEditSheet: View {
    @Environment(\.pinesTheme) private var theme
    let message: ChatMessage
    let cancel: () -> Void
    let save: (String) -> Void
    @State private var draft: String

    init(message: ChatMessage, cancel: @escaping () -> Void, save: @escaping (String) -> Void) {
        self.message = message
        self.cancel = cancel
        self.save = save
        _draft = State(initialValue: message.content)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: theme.spacing.medium) {
                TextEditor(text: $draft)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.primaryText)
                    .scrollContentBackground(.hidden)
                    .padding(theme.spacing.small)
                    .frame(minHeight: 220)
                    .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                            .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)
                    }

                if !message.attachments.isEmpty {
                    ChatAttachmentList(attachments: message.attachments)
                }
            }
            .padding(theme.spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.colors.sheetBackground.ignoresSafeArea())
            .navigationTitle("Edit Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(draft)
                    }
                    .disabled(!canSave || draft == message.content)
                }
            }
        }
        .pinesDismissKeyboardOnSwipeDown()
        .presentationDetents([.medium, .large])
    }

    private var canSave: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !message.attachments.isEmpty
    }
}

struct ChatAttachmentList: View {
    @Environment(\.pinesTheme) private var theme
    let attachments: [ChatAttachment]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            ForEach(attachments.indices, id: \.self) { index in
                let attachment = attachments[index]
                HStack(spacing: theme.spacing.xsmall) {
                    Image(systemName: Self.iconName(for: attachment))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(attachment.fileName)
                            .font(theme.typography.caption.weight(.medium))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(Self.detailText(for: attachment))
                            .font(.caption2)
                            .foregroundStyle(theme.colors.tertiaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: theme.spacing.small)
                }
                .padding(.horizontal, theme.spacing.small)
                .padding(.vertical, theme.spacing.xsmall)
                .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(attachments.count) attachments")
    }

    static func iconName(for attachment: ChatAttachment) -> String {
        switch attachment.kind {
        case .image:
            "photo"
        case .document:
            attachment.normalizedContentType == "application/pdf" ? "doc.richtext" : "doc.text"
        case .webCapture:
            "globe"
        case .audio:
            "waveform"
        case .video:
            "film"
        }
    }

    static func detailText(for attachment: ChatAttachment) -> String {
        let size = attachment.byteCount > 0
            ? ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file)
            : "Unknown size"
        return "\(attachment.contentType) - \(size)"
    }
}

private extension ChatRole {
    var title: String {
        switch self {
        case .system:
            "System"
        case .user:
            "You"
        case .assistant:
            "Pines"
        case .tool:
            "Tool"
        }
    }

    func tint(in theme: PinesTheme) -> Color {
        switch self {
        case .system:
            theme.colors.warning
        case .user:
            theme.colors.info
        case .assistant:
            theme.colors.accent
        case .tool:
            theme.colors.tertiaryText
        }
    }

    func bubbleFill(in theme: PinesTheme) -> AnyShapeStyle {
        switch self {
        case .system:
            AnyShapeStyle(theme.colors.toolBubble)
        case .user:
            AnyShapeStyle(theme.colors.userBubble)
        case .assistant:
            AnyShapeStyle(theme.colors.assistantBubble)
        case .tool:
            AnyShapeStyle(theme.colors.toolBubble)
        }
    }

    func bubbleBorder(in theme: PinesTheme) -> Color {
        switch self {
        case .system:
            theme.colors.warning.opacity(0.24)
        case .user:
            theme.colors.info.opacity(0.24)
        case .assistant:
            theme.colors.accent.opacity(0.24)
        case .tool:
            theme.colors.separator
        }
    }
}

struct ChatQuickSettingsButton: View {
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var haptics: PinesHaptics
    let availability: ChatQuickSettingsAvailability

    var body: some View {
        Menu {
            if !availability.openAIReasoningEfforts.isEmpty {
                Section("OpenAI Reasoning Effort") {
                    ForEach(availability.openAIReasoningEfforts, id: \.self) { effort in
                        Button {
                            reasoningSelection.wrappedValue = effort
                        } label: {
                            quickSettingLabel(effort.shortTitle, isSelected: reasoningSelection.wrappedValue == effort)
                        }
                    }
                }
            }

            if availability.supportsOpenAITextVerbosity {
                Section("OpenAI Text Verbosity") {
                    ForEach(OpenAITextVerbosity.quickSettingOptions, id: \.self) { verbosity in
                        Button {
                            verbositySelection.wrappedValue = verbosity
                        } label: {
                            quickSettingLabel(verbosity.shortTitle, isSelected: verbositySelection.wrappedValue == verbosity)
                        }
                    }
                }
            }

            if !availability.anthropicThinkingModes.isEmpty {
                Section("Anthropic Thinking") {
                    ForEach(availability.anthropicThinkingModes, id: \.self) { mode in
                        Button {
                            anthropicThinkingModeSelection.wrappedValue = mode
                        } label: {
                            quickSettingLabel(mode.shortTitle, isSelected: anthropicThinkingModeSelection.wrappedValue == mode)
                        }
                    }
                }
            }

            if !availability.anthropicThinkingModes.isEmpty, anthropicThinkingModeSelection.wrappedValue == .budgeted {
                Section("Anthropic Budget") {
                    ForEach([4096, 8192, 16384], id: \.self) { budget in
                        Button {
                            anthropicThinkingBudgetSelection.wrappedValue = budget
                        } label: {
                            quickSettingLabel("\(budget) tokens", isSelected: anthropicThinkingBudgetSelection.wrappedValue == budget)
                        }
                    }
                }
            }

            if !availability.anthropicEfforts.isEmpty, anthropicThinkingModeSelection.wrappedValue == .effort {
                Section("Anthropic Effort") {
                    ForEach(availability.anthropicEfforts, id: \.self) { effort in
                        Button {
                            anthropicEffortSelection.wrappedValue = effort
                        } label: {
                            quickSettingLabel(effort.shortTitle, isSelected: anthropicEffortSelection.wrappedValue == effort)
                        }
                    }
                }
            }

            if !availability.anthropicThinkingModes.isEmpty {
                Section("Anthropic Prompt Cache") {
                    Toggle("Cache prompts", isOn: anthropicPromptCacheEnabledSelection)
                    ForEach(AnthropicPromptCacheTTL.allCases, id: \.self) { ttl in
                        Button {
                            anthropicPromptCacheTTLSelection.wrappedValue = ttl
                        } label: {
                            quickSettingLabel(ttl.shortTitle, isSelected: anthropicPromptCacheTTLSelection.wrappedValue == ttl)
                        }
                    }
                    Toggle("Citations", isOn: anthropicCitationsEnabledSelection)
                    Toggle("Token preflight", isOn: anthropicTokenCountPreflightSelection)
                }
            }

            if !availability.geminiThinkingLevels.isEmpty {
                Section("Gemini Thinking Level") {
                    ForEach(availability.geminiThinkingLevels, id: \.self) { level in
                        Button {
                            geminiThinkingSelection.wrappedValue = level
                        } label: {
                            quickSettingLabel(level.shortTitle, isSelected: geminiThinkingSelection.wrappedValue == level)
                        }
                    }
                }
            }

            if !availability.cloudWebSearchModes.isEmpty {
                Section("Provider Web Search") {
                    ForEach(availability.cloudWebSearchModes, id: \.self) { mode in
                        Button {
                            cloudWebSearchSelection.wrappedValue = mode
                        } label: {
                            quickSettingLabel(mode.shortTitle, isSelected: cloudWebSearchSelection.wrappedValue == mode)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            theme.colors.primaryText,
                            theme.colors.accent
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: theme.radius.control + 6, style: .continuous)
                        .fill(theme.colors.glassSurface)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    theme.colors.surfaceHighlight.opacity(0.95),
                                    theme.colors.accentSoft.opacity(0.34),
                                    theme.colors.controlFill.opacity(0.76)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: theme.radius.control + 6, style: .continuous))
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radius.control + 6, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    theme.colors.surfaceHighlight.opacity(0.90),
                                    theme.colors.accent.opacity(0.32),
                                    theme.colors.controlBorder.opacity(0.70)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: theme.stroke.hairline
                        )
                }
                .shadow(color: theme.colors.accent.opacity(theme.colorScheme == .dark ? 0.18 : 0.12), radius: theme.shadow.panelRadius * 0.32, x: 0, y: theme.shadow.panelY * 0.18)
                .contentShape(RoundedRectangle(cornerRadius: theme.radius.control + 6, style: .continuous))
        }
        .accessibilityLabel("Model quick settings")
        .accessibilityIdentifier("pines.chat.model.quick-settings")
        .accessibilityValue(accessibilityValue)
        .simultaneousGesture(TapGesture().onEnded { haptics.play(.navigationSelected) })
    }

    @ViewBuilder
    private func quickSettingLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var reasoningSelection: Binding<OpenAIReasoningEffort> {
        Binding {
            availability.openAIReasoningEfforts.contains(settingsState.openAIReasoningEffort)
                ? settingsState.openAIReasoningEffort
                : defaultReasoningEffort
        } set: { effort in
            settingsState.openAIReasoningEffort = effort
            haptics.play(.primaryAction)
        }
    }

    private var verbositySelection: Binding<OpenAITextVerbosity> {
        Binding {
            settingsState.openAITextVerbosity
        } set: { verbosity in
            settingsState.openAITextVerbosity = verbosity
            haptics.play(.primaryAction)
        }
    }

    private var anthropicEffortSelection: Binding<AnthropicEffort> {
        Binding {
            availability.anthropicEfforts.contains(settingsState.anthropicEffort)
                ? settingsState.anthropicEffort
                : defaultAnthropicEffort
        } set: { effort in
            settingsState.anthropicEffort = effort
            haptics.play(.primaryAction)
        }
    }

    private var anthropicThinkingModeSelection: Binding<AnthropicThinkingMode> {
        Binding {
            availability.anthropicThinkingModes.contains(settingsState.anthropicThinkingMode)
                ? settingsState.anthropicThinkingMode
                : defaultAnthropicThinkingMode
        } set: { mode in
            settingsState.anthropicThinkingMode = availability.anthropicThinkingModes.contains(mode) ? mode : defaultAnthropicThinkingMode
            haptics.play(.primaryAction)
        }
    }

    private var anthropicThinkingBudgetSelection: Binding<Int> {
        Binding {
            settingsState.anthropicThinkingBudgetTokens
        } set: { budget in
            settingsState.anthropicThinkingBudgetTokens = AppSettingsSnapshot.normalizedAnthropicThinkingBudgetTokens(budget)
            haptics.play(.primaryAction)
        }
    }

    private var anthropicPromptCacheEnabledSelection: Binding<Bool> {
        Binding {
            settingsState.anthropicPromptCachingEnabled
        } set: { enabled in
            settingsState.anthropicPromptCachingEnabled = enabled
            haptics.play(.primaryAction)
        }
    }

    private var anthropicPromptCacheTTLSelection: Binding<AnthropicPromptCacheTTL> {
        Binding {
            settingsState.anthropicPromptCacheTTL
        } set: { ttl in
            settingsState.anthropicPromptCacheTTL = ttl
            haptics.play(.primaryAction)
        }
    }

    private var anthropicCitationsEnabledSelection: Binding<Bool> {
        Binding {
            settingsState.anthropicCitationsEnabled
        } set: { enabled in
            settingsState.anthropicCitationsEnabled = enabled
            haptics.play(.primaryAction)
        }
    }

    private var anthropicTokenCountPreflightSelection: Binding<Bool> {
        Binding {
            settingsState.anthropicTokenCountPreflightEnabled
        } set: { enabled in
            settingsState.anthropicTokenCountPreflightEnabled = enabled
            haptics.play(.primaryAction)
        }
    }

    private var geminiThinkingSelection: Binding<GeminiThinkingLevel> {
        Binding {
            availability.geminiThinkingLevels.contains(settingsState.geminiThinkingLevel)
                ? settingsState.geminiThinkingLevel
                : defaultGeminiThinkingLevel
        } set: { level in
            settingsState.geminiThinkingLevel = level
            haptics.play(.primaryAction)
        }
    }

    private var cloudWebSearchSelection: Binding<CloudWebSearchMode> {
        Binding {
            if availability.cloudWebSearchModes.contains(settingsState.cloudWebSearchMode) {
                return settingsState.cloudWebSearchMode
            }
            if settingsState.cloudWebSearchMode == .required, availability.cloudWebSearchModes.contains(.automatic) {
                return .automatic
            }
            return .off
        } set: { mode in
            settingsState.cloudWebSearchMode = availability.cloudWebSearchModes.contains(mode) ? mode : .off
            haptics.play(.primaryAction)
        }
    }

    private var defaultReasoningEffort: OpenAIReasoningEffort {
        if availability.openAIReasoningEfforts.contains(.low) {
            return .low
        }
        return availability.openAIReasoningEfforts.first ?? AppSettingsSnapshot.defaultOpenAIReasoningEffort
    }

    private var defaultAnthropicEffort: AnthropicEffort {
        if availability.anthropicEfforts.contains(.medium) {
            return .medium
        }
        if availability.anthropicEfforts.contains(.low) {
            return .low
        }
        return availability.anthropicEfforts.first ?? AppSettingsSnapshot.defaultAnthropicEffort
    }

    private var defaultAnthropicThinkingMode: AnthropicThinkingMode {
        if availability.anthropicThinkingModes.contains(.adaptive) {
            return .adaptive
        }
        return availability.anthropicThinkingModes.first ?? AppSettingsSnapshot.defaultAnthropicThinkingMode
    }

    private var defaultGeminiThinkingLevel: GeminiThinkingLevel {
        if availability.geminiThinkingLevels.contains(.medium) {
            return .medium
        }
        if availability.geminiThinkingLevels.contains(.low) {
            return .low
        }
        return availability.geminiThinkingLevels.first ?? AppSettingsSnapshot.defaultGeminiThinkingLevel
    }

    private var accessibilityValue: String {
        var parts = [String]()
        if !availability.openAIReasoningEfforts.isEmpty {
            parts.append("OpenAI reasoning effort \(reasoningSelection.wrappedValue.shortTitle)")
        }
        if availability.supportsOpenAITextVerbosity {
            parts.append("OpenAI text verbosity \(settingsState.openAITextVerbosity.shortTitle)")
        }
        if !availability.anthropicThinkingModes.isEmpty {
            parts.append("Anthropic thinking \(anthropicThinkingModeSelection.wrappedValue.shortTitle)")
            parts.append("Anthropic cache \(settingsState.anthropicPromptCachingEnabled ? settingsState.anthropicPromptCacheTTL.rawValue : "off")")
            if settingsState.anthropicTokenCountPreflightEnabled {
                parts.append("Anthropic token preflight on")
            }
        }
        if !availability.anthropicEfforts.isEmpty, anthropicThinkingModeSelection.wrappedValue == .effort {
            parts.append("Anthropic effort \(anthropicEffortSelection.wrappedValue.shortTitle)")
        }
        if !availability.geminiThinkingLevels.isEmpty {
            parts.append("Gemini thinking level \(geminiThinkingSelection.wrappedValue.shortTitle)")
        }
        if !availability.cloudWebSearchModes.isEmpty {
            parts.append("provider web search \(cloudWebSearchSelection.wrappedValue.shortTitle)")
        }
        return parts.joined(separator: ", ")
    }
}

private extension CloudWebSearchMode {
    var shortTitle: String {
        switch self {
        case .off:
            "Off"
        case .automatic:
            "Auto"
        case .required:
            "Required"
        }
    }
}

private extension OpenAIReasoningEffort {
    var shortTitle: String {
        switch self {
        case .none:
            "None"
        case .minimal:
            "Minimal"
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        case .xhigh:
            "X High"
        }
    }
}

private extension OpenAITextVerbosity {
    static let quickSettingOptions: [OpenAITextVerbosity] = [.low, .medium, .high]

    var shortTitle: String {
        switch self {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }
}

private extension AnthropicEffort {
    var shortTitle: String {
        switch self {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        case .xhigh:
            "X High"
        case .max:
            "Max"
        }
    }
}

private extension AnthropicThinkingMode {
    var shortTitle: String {
        switch self {
        case .off:
            "Off"
        case .adaptive:
            "Adaptive"
        case .budgeted:
            "Budget"
        case .effort:
            "Effort"
        }
    }
}

private extension AnthropicPromptCacheTTL {
    var shortTitle: String {
        switch self {
        case .fiveMinutes:
            "5 min"
        case .oneHour:
            "1 hour"
        }
    }
}

private extension GeminiThinkingLevel {
    var shortTitle: String {
        switch self {
        case .minimal:
            "Minimal"
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }
}
