public struct CalculatorInput: ToolInput, Equatable {
    public let expression: String

    public init(expression: String) {
        self.expression = expression
    }
}

public struct CalculatorOutput: ToolOutput, Equatable {
    public let value: Double
    public let formatted: String

    public init(value: Double, formatted: String) {
        self.value = value
        self.formatted = formatted
    }
}

public enum CalculatorTool {
    public static let name = "calculator.evaluate"

    public static func spec(
        evaluator: SafeCalculatorEvaluator = SafeCalculatorEvaluator()
    ) throws -> ToolSpec<CalculatorInput, CalculatorOutput> {
        try ToolSpec(
            name: name,
            description: "Evaluate a safe arithmetic expression.",
            inputSchema: ToolIOSchema(
                properties: [
                    "expression": ToolParameterSpec(
                        type: .string,
                        description: "Arithmetic expression using numbers, parentheses, +, -, *, /, and ^."
                    ),
                ],
                required: ["expression"]
            ),
            outputSchema: ToolIOSchema(
                properties: [
                    "value": ToolParameterSpec(type: .number, description: "Numeric result."),
                    "formatted": ToolParameterSpec(type: .string, description: "Display-ready result."),
                ],
                required: ["value", "formatted"]
            ),
            permissions: [.localComputation],
            sideEffect: .none,
            networkPolicy: .noNetwork,
            timeoutSeconds: 2,
            explanationRequired: true
        ) { input in
            let value = try evaluator.evaluate(input.expression)
            return CalculatorOutput(value: value, formatted: Self.format(value))
        }
    }

    private static func format(_ value: Double) -> String {
        guard value != 0 else {
            return "0"
        }

        let rounded = value.rounded()
        if rounded == value,
           rounded >= Double(Int64.min),
           rounded <= Double(Int64.max) {
            return String(Int64(rounded))
        }

        return String(value)
    }
}
