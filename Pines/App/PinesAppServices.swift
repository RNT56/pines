import Foundation
import SwiftUI
import PinesCore

final class PinesAppServices: @unchecked Sendable {
    let secretStore: any SecretStore
    let modelCatalog: HuggingFaceModelCatalogService
    let preflightClassifier: ModelPreflightClassifier
    let executionRouter: ExecutionRouter
    let toolRegistry: ToolRegistry
    let toolPolicyGate: ToolPolicyGate
    let redactor: Redactor
    let mlxRuntime: MLXRuntimeBridge

    init(
        secretStore: any SecretStore = KeychainSecretStore(),
        modelCatalog: HuggingFaceModelCatalogService = HuggingFaceModelCatalogService(),
        preflightClassifier: ModelPreflightClassifier = ModelPreflightClassifier(),
        executionRouter: ExecutionRouter = ExecutionRouter(),
        toolRegistry: ToolRegistry = ToolRegistry(),
        toolPolicyGate: ToolPolicyGate = ToolPolicyGate(),
        redactor: Redactor = Redactor(),
        mlxRuntime: MLXRuntimeBridge = MLXRuntimeBridge()
    ) {
        self.secretStore = secretStore
        self.modelCatalog = modelCatalog
        self.preflightClassifier = preflightClassifier
        self.executionRouter = executionRouter
        self.toolRegistry = toolRegistry
        self.toolPolicyGate = toolPolicyGate
        self.redactor = redactor
        self.mlxRuntime = mlxRuntime
    }

    func bootstrap() async {
        try? await toolRegistry.register(CalculatorTool.spec())
        try? await toolRegistry.register(BuiltInToolSpecs.webSearchSpec())
        try? await toolRegistry.register(BuiltInToolSpecs.browserObserveSpec())
    }

    var serviceHealth: [ServiceHealth] {
        [
            ServiceHealth(
                name: "MLX Runtime",
                readiness: mlxRuntime.isLinked ? .ready : .requiresUserAction,
                summary: mlxRuntime.isLinked ? "MLX packages are linked." : "Open with full Xcode to resolve iOS MLX packages."
            ),
            ServiceHealth(
                name: "Tool Registry",
                readiness: .ready,
                summary: "Calculator, web-search, and browser tool specs are registered at boot."
            ),
            ServiceHealth(
                name: "Privacy Boundary",
                readiness: .ready,
                summary: "Cloud execution remains opt-in through agent policy."
            ),
        ]
    }
}

private struct PinesAppServicesKey: EnvironmentKey {
    static let defaultValue = PinesAppServices()
}

extension EnvironmentValues {
    var pinesServices: PinesAppServices {
        get { self[PinesAppServicesKey.self] }
        set { self[PinesAppServicesKey.self] = newValue }
    }
}
