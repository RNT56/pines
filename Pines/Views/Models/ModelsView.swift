import SwiftUI
import PinesCore

struct ModelsView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var modelState: PinesModelState
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var selectedModelKey: String?
    @State private var selectedTaskFilter: HubTask?
    @State private var selectedVerificationFilter: ModelVerificationState?
    @State private var selectedInstallStateFilter: ModelInstallState?
    @State private var searchInput = ModelSearchInputState()
    @State private var appliedSearchCriteria = ModelSearchCriteria()

    private var selectedModel: PinesModelPreview? {
        guard let selectedModelKey else { return nil }
        return displayedModels.first { $0.selectionKey == selectedModelKey }
    }

    private var displayedModels: [PinesModelPreview] {
        guard !appliedSearchCriteria.hasDiscoveryCriteria else { return modelState.models }
        return modelState.models.filter { model in
            model.install.state == .installed || model.install.state == .failed || model.hasActiveDownload
        }
    }

    private var searchCriteria: ModelSearchCriteria {
        ModelSearchCriteria(
            query: searchInput.text,
            task: selectedTaskFilter,
            verification: selectedVerificationFilter,
            installState: selectedInstallStateFilter
        )
    }

    private var isDiscovering: Bool {
        appliedSearchCriteria.hasDiscoveryCriteria
    }

    private var modelSectionTitle: String {
        if modelState.isSearchingModels {
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
                defaultModelID: modelState.defaultModelID,
                isSearching: modelState.isSearchingModels,
                searchError: modelState.modelSearchError,
                sectionTitle: modelSectionTitle,
                isDiscovering: isDiscovering
            )
            .navigationTitle("Models")
            .pinesExpressiveScrollHaptics()
            .searchable(text: searchTextBinding, prompt: "Search Hugging Face")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .task {
                appliedSearchCriteria = ModelSearchCriteria()
                await appModel.searchModels(query: "", services: services)
            }
            .onChange(of: selectedTaskFilter) { _, _ in scheduleModelSearch(searchCriteria) }
            .onChange(of: selectedVerificationFilter) { _, _ in scheduleModelSearch(searchCriteria) }
            .onChange(of: selectedInstallStateFilter) { _, _ in scheduleModelSearch(searchCriteria) }
            .onDisappear {
                searchInput.cancelScheduledSearch()
            }
            .onChange(of: selectedModelKey) { _, _ in
                haptics.play(.navigationSelected)
            }
            .onChange(of: modelState.models) { _, models in
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
        } detail: {
            if let selectedModel {
                ModelDetailView(model: selectedModel)
            } else {
                PinesEmptyState(
                    title: "No models",
                    detail: "Search Hugging Face or install a curated local MLX model.",
                    systemImage: "cpu",
                    primaryActionTitle: "Browse MLX models",
                    primaryActionSystemImage: "magnifyingglass"
                ) {
                    let criteria = ModelSearchCriteria(query: "mlx")
                    searchInput.text = criteria.query
                    scheduleModelSearch(criteria)
                }
            }
        }
        .accessibilityIdentifier("pines.screen.models")
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { searchInput.text },
            set: { newValue in
                searchInput.text = newValue
                scheduleModelSearch(searchCriteria)
            }
        )
    }

    private func scheduleModelSearch(_ criteria: ModelSearchCriteria) {
        searchInput.scheduledTask?.cancel()
        searchInput.scheduledTask = Task {
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

private final class ModelSearchInputState {
    var text = ""
    var scheduledTask: Task<Void, Never>?

    func cancelScheduledSearch() {
        scheduledTask?.cancel()
        scheduledTask = nil
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
