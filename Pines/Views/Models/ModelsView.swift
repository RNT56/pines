import SwiftUI
import PinesCore

struct ModelsView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var selectedModelKey: String?
    @State private var searchText = ""
    @State private var selectedTaskFilter: HubTask?
    @State private var selectedVerificationFilter: ModelVerificationState?
    @State private var selectedInstallStateFilter: ModelInstallState?
    @State private var scheduledSearchTask: Task<Void, Never>?
    @State private var appliedSearchCriteria = ModelSearchCriteria()

    private var selectedModel: PinesModelPreview? {
        guard let selectedModelKey else { return nil }
        return displayedModels.first { $0.selectionKey == selectedModelKey }
    }

    private var displayedModels: [PinesModelPreview] {
        guard !appliedSearchCriteria.hasDiscoveryCriteria else { return appModel.models }
        return appModel.models.filter { model in
            model.install.state == .installed || model.install.state == .failed || model.hasActiveDownload
        }
    }

    private var searchCriteria: ModelSearchCriteria {
        ModelSearchCriteria(
            query: searchText,
            task: selectedTaskFilter,
            verification: selectedVerificationFilter,
            installState: selectedInstallStateFilter
        )
    }

    private var isDiscovering: Bool {
        appliedSearchCriteria.hasDiscoveryCriteria
    }

    private var modelSectionTitle: String {
        if appModel.isSearchingModels {
            return "Searching Hugging Face"
        }
        return isDiscovering ? "MLX Hub results" : "Installed models"
    }

    var body: some View {
        NavigationSplitView {
            ModelSidebarList(
                selectedModelKey: $selectedModelKey,
                selectedTaskFilter: $selectedTaskFilter,
                selectedVerificationFilter: $selectedVerificationFilter,
                selectedInstallStateFilter: $selectedInstallStateFilter,
                models: displayedModels,
                defaultModelID: appModel.defaultModelID,
                isSearching: appModel.isSearchingModels,
                searchError: appModel.modelSearchError,
                sectionTitle: modelSectionTitle,
                isDiscovering: isDiscovering
            )
            .navigationTitle("Models")
            .pinesExpressiveScrollHaptics()
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
                    .disabled(selectedModel == nil || selectedModel?.install.state == .installed || selectedModel?.hasActiveDownload == true || selectedModel?.status == .unsupported)

                    Button {
                        if let selectedModel {
                            haptics.play(.destructiveAction)
                            Task {
                                await appModel.cancelModelDownload(repository: selectedModel.install.repository, services: services)
                            }
                        }
                    } label: {
                        Image(systemName: "stop.circle")
                    }
                    .accessibilityLabel("Cancel model download")
                    .disabled(selectedModel?.hasActiveDownload != true)

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
                    .disabled(selectedModel == nil || selectedModel?.canDeleteModel != true)
                }
            }
            .searchable(text: $searchText, prompt: "Search Hugging Face")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .task {
                appliedSearchCriteria = ModelSearchCriteria()
                await appModel.searchModels(query: "", services: services)
            }
            .onChange(of: searchCriteria) { _, criteria in
                scheduleModelSearch(criteria)
            }
            .onDisappear {
                scheduledSearchTask?.cancel()
                scheduledSearchTask = nil
            }
            .onChange(of: selectedModelKey) { _, _ in
                haptics.play(.navigationSelected)
            }
            .onChange(of: appModel.models) { _, models in
                guard let currentSelection = selectedModelKey else { return }
                if !models.contains(where: { $0.selectionKey == currentSelection }) || !displayedModels.contains(where: { $0.selectionKey == currentSelection }) {
                    self.selectedModelKey = nil
                }
            }
            .onChange(of: appliedSearchCriteria) { _, _ in
                guard let currentSelection = selectedModelKey else { return }
                if !displayedModels.contains(where: { $0.selectionKey == currentSelection }) {
                    self.selectedModelKey = nil
                }
            }
            .pinesSidebarListChrome()
            .animation(theme.motion.fast, value: appModel.isSearchingModels)
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

    private func scheduleModelSearch(_ criteria: ModelSearchCriteria) {
        scheduledSearchTask?.cancel()
        scheduledSearchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                appliedSearchCriteria = criteria
            }
            await appModel.searchModels(
                query: criteria.query,
                task: criteria.task,
                verification: criteria.verification,
                installState: criteria.installState,
                services: services
            )
        }
    }
}

extension PinesModelPreview {
    var selectionKey: String {
        install.repository.lowercased()
    }
}

private struct ModelSearchCriteria: Hashable {
    var query: String
    var task: HubTask?
    var verification: ModelVerificationState?
    var installState: ModelInstallState?

    init(
        query: String = "",
        task: HubTask? = nil,
        verification: ModelVerificationState? = nil,
        installState: ModelInstallState? = nil
    ) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.task = task
        self.verification = verification
        self.installState = installState
    }

    var hasDiscoveryCriteria: Bool {
        !query.isEmpty || task != nil || verification != nil || installState != nil
    }
}
