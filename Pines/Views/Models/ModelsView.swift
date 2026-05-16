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
        guard let selectedModelID else { return nil }
        return displayedModels.first { $0.id == selectedModelID }
    }

    private var displayedModels: [PinesModelPreview] {
        guard !isDiscovering else { return appModel.models }
        return appModel.models.filter { model in
            model.install.state == .installed || model.install.state == .failed || model.hasActiveDownload
        }
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
        return isDiscovering ? "MLX Hub results" : "Installed models"
    }

    var body: some View {
        NavigationSplitView {
            ModelSidebarList(
                selectedModelID: $selectedModelID,
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
            .onChange(of: selectedModelID) { _, _ in
                haptics.play(.navigationSelected)
            }
            .onChange(of: appModel.models) { _, models in
                guard let currentSelection = selectedModelID else { return }
                if !models.contains(where: { $0.id == currentSelection }) || !displayedModels.contains(where: { $0.id == currentSelection }) {
                    self.selectedModelID = nil
                }
            }
            .onChange(of: searchFingerprint) { _, _ in
                guard let currentSelection = selectedModelID else { return }
                if !displayedModels.contains(where: { $0.id == currentSelection }) {
                    self.selectedModelID = nil
                }
            }
            .pinesSidebarListChrome()
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
