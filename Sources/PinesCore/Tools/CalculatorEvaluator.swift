import Foundation

public enum CalculatorEvaluationError: Error, Equatable, CustomStringConvertible, Sendable {
    case divisionByZero
    case emptyExpression
    case expressionTooLong(maximum: Int)
    case invalidCharacter(String, position: Int)
    case invalidNumber(String, position: Int)
    case nonFiniteResult
    case unexpectedEnd
    case unexpectedToken(String, position: Int)
    case unclosedParenthesis(position: Int)

    public var description: String {
        switch self {
        case .divisionByZero:
            "Division by zero is not allowed."
        case .emptyExpression:
            "Expression must not be empty."
        case let .expressionTooLong(maximum):
            "Expression must be \(maximum) characters or fewer."
        case let .invalidCharacter(character, position):
            "Invalid character \(character) at position \(position)."
        case let .invalidNumber(number, position):
            "Invalid number \(number) at position \(position)."
        case .nonFiniteResult:
            "Expression result is not finite."
        case .unexpectedEnd:
            "Expression ended before it was complete."
        case let .unexpectedToken(token, position):
            "Unexpected token \(token) at position \(position)."
        case let .unclosedParenthesis(position):
            "Unclosed parenthesis at position \(position)."
        }
    }
}

public struct SafeCalculatorEvaluator: Sendable {
    public let maximumExpressionLength: Int

    public init(maximumExpressionLength: Int = 256) {
        precondition(maximumExpressionLength > 0, "maximumExpressionLength must be positive")
        self.maximumExpressionLength = maximumExpressionLength
    }

    public func evaluate(_ expression: String) throws -> Double {
        let bytes = Array(expression.utf8)

        guard bytes.count <= maximumExpressionLength else {
            throw CalculatorEvaluationError.expressionTooLong(maximum: maximumExpressionLength)
        }

        guard bytes.contains(where: { !CalculatorParser.isWhitespace($0) }) else {
            throw CalculatorEvaluationError.emptyExpression
        }

        var parser = CalculatorParser(bytes: bytes)
        return try parser.parse()
    }
}

private struct CalculatorParser {
    let bytes: [UInt8]
    var index = 0

    mutating func parse() throws -> Double {
        let value = try parseExpression()
        skipWhitespace()

        guard index == bytes.count else {
            let token = describeByte(at: index)
            if Self.isKnownToken(bytes[index]) {
                throw CalculatorEvaluationError.unexpectedToken(token, position: index)
            }
            throw CalculatorEvaluationError.invalidCharacter(token, position: index)
        }

        return try checked(value)
    }

    private mutating func parseExpression() throws -> Double {
        var value = try parseTerm()

        while true {
            if match(Self.plus) {
                value = try checked(value + parseTerm())
            } else if match(Self.minus) {
                value = try checked(value - parseTerm())
            } else {
                return value
            }
        }
    }

    private mutating func parseTerm() throws -> Double {
        var value = try parseUnary()

        while true {
            if match(Self.asterisk) {
                value = try checked(value * parseUnary())
            } else if match(Self.slash) {
                let divisor = try parseUnary()
                guard divisor != 0 else {
                    throw CalculatorEvaluationError.divisionByZero
                }
                value = try checked(value / divisor)
            } else {
                return value
            }
        }
    }

    private mutating func parseUnary() throws -> Double {
        if match(Self.plus) {
            return try checked(parseUnary())
        }

        if match(Self.minus) {
            return try checked(-parseUnary())
        }

        return try parsePower()
    }

    private mutating func parsePower() throws -> Double {
        let base = try parsePrimary()

        guard match(Self.caret) else {
            return base
        }

        let exponent = try parseUnary()
        return try checked(pow(base, exponent))
    }

    private mutating func parsePrimary() throws -> Double {
        skipWhitespace()

        guard index < bytes.count else {
            throw CalculatorEvaluationError.unexpectedEnd
        }

        if match(Self.openParenthesis) {
            let openPosition = index - 1
            let value = try parseExpression()
            skipWhitespace()

            guard match(Self.closeParenthesis) else {
                if index == bytes.count {
                    throw CalculatorEvaluationError.unclosedParenthesis(position: openPosition)
                }

                let token = describeByte(at: index)
                if Self.isKnownToken(bytes[index]) {
                    throw CalculatorEvaluationError.unexpectedToken(token, position: index)
                }
                throw CalculatorEvaluationError.invalidCharacter(token, position: index)
            }

            return try checked(value)
        }

        let byte = bytes[index]
        if Self.isDigit(byte) || byte == Self.period {
            return try parseNumber()
        }

        let token = describeByte(at: index)
        if Self.isKnownToken(byte) {
            throw CalculatorEvaluationError.unexpectedToken(token, position: index)
        }
        throw CalculatorEvaluationError.invalidCharacter(token, position: index)
    }

    private mutating func parseNumber() throws -> Double {
        let start = index
        var sawDigit = false

        while index < bytes.count, Self.isDigit(bytes[index]) {
            sawDigit = true
            index += 1
        }

        if index < bytes.count, bytes[index] == Self.period {
            index += 1

            while index < bytes.count, Self.isDigit(bytes[index]) {
                sawDigit = true
                index += 1
            }
        }

        guard sawDigit else {
            let literal = String(decoding: bytes[start..<index], as: UTF8.self)
            throw CalculatorEvaluationError.invalidNumber(literal, position: start)
        }

        if index < bytes.count, bytes[index] == Self.lowercaseE || bytes[index] == Self.uppercaseE {
            index += 1

            if index < bytes.count, bytes[index] == Self.plus || bytes[index] == Self.minus {
                index += 1
            }

            let exponentStart = index
            while index < bytes.count, Self.isDigit(bytes[index]) {
                index += 1
            }

            guard exponentStart < index else {
                let literal = String(decoding: bytes[start..<index], as: UTF8.self)
                throw CalculatorEvaluationError.invalidNumber(literal, position: start)
            }
        }

        let literal = String(decoding: bytes[start..<index], as: UTF8.self)
        guard let value = Double(literal) else {
            throw CalculatorEvaluationError.invalidNumber(literal, position: start)
        }

        return try checked(value)
    }

    private mutating func match(_ byte: UInt8) -> Bool {
        skipWhitespace()

        guard index < bytes.count, bytes[index] == byte else {
            return false
        }

        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, Self.isWhitespace(bytes[index]) {
            index += 1
        }
    }

    private func checked(_ value: Double) throws -> Double {
        guard value.isFinite else {
            throw CalculatorEvaluationError.nonFiniteResult
        }

        if value == 0 {
            return 0
        }

        return value
    }

    private func describeByte(at position: Int) -> String {
        guard position < bytes.count else {
            return "end of expression"
        }

        let byte = bytes[position]
        if byte >= 32, byte <= 126, let scalar = UnicodeScalar(Int(byte)) {
            return String(scalar)
        }

        return "non-ASCII"
    }

    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 9 || byte == 10 || byte == 13 || byte == 32
    }

    private static func isKnownToken(_ byte: UInt8) -> Bool {
        isDigit(byte)
            || byte == period
            || byte == plus
            || byte == minus
            || byte == asterisk
            || byte == slash
            || byte == caret
            || byte == openParenthesis
            || byte == closeParenthesis
            || byte == lowercaseE
            || byte == uppercaseE
            || isWhitespace(byte)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= 48 && byte <= 57
    }

    private static let lowercaseE = UInt8(ascii: "e")
    private static let uppercaseE = UInt8(ascii: "E")
    private static let period = UInt8(ascii: ".")
    private static let plus = UInt8(ascii: "+")
    private static let minus = UInt8(ascii: "-")
    private static let asterisk = UInt8(ascii: "*")
    private static let slash = UInt8(ascii: "/")
    private static let caret = UInt8(ascii: "^")
    private static let openParenthesis = UInt8(ascii: "(")
    private static let closeParenthesis = UInt8(ascii: ")")
}
