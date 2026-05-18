import Foundation

public struct TimeNowInput: ToolInput, Equatable {
    public let timeZone: String?

    public init(timeZone: String? = nil) {
        self.timeZone = timeZone
    }
}

public struct TimeNowOutput: ToolOutput, Equatable {
    public let iso8601: String
    public let unixTime: Double
    public let timeZoneIdentifier: String
    public let secondsFromGMT: Int
    public let calendarIdentifier: String
    public let localeIdentifier: String

    public init(
        iso8601: String,
        unixTime: Double,
        timeZoneIdentifier: String,
        secondsFromGMT: Int,
        calendarIdentifier: String,
        localeIdentifier: String
    ) {
        self.iso8601 = iso8601
        self.unixTime = unixTime
        self.timeZoneIdentifier = timeZoneIdentifier
        self.secondsFromGMT = secondsFromGMT
        self.calendarIdentifier = calendarIdentifier
        self.localeIdentifier = localeIdentifier
    }
}

public enum TimeNowTool {
    public static let name = "time.now"

    public static func spec(now: @escaping @Sendable () -> Date = Date.init) throws -> ToolSpec<TimeNowInput, TimeNowOutput> {
        try ToolSpec(
            name: name,
            description: "Return the current local date and time with timezone, calendar, locale, and Unix timestamp.",
            inputSchema: ToolIOSchema(
                properties: [
                    "timeZone": .init(type: .string, description: "Optional IANA timezone identifier. Defaults to the device timezone."),
                ]
            ),
            outputSchema: ToolIOSchema(
                properties: [
                    "iso8601": .init(type: .string, description: "Current time formatted as ISO-8601 in the requested timezone."),
                    "unixTime": .init(type: .number, description: "Seconds since the Unix epoch."),
                    "timeZoneIdentifier": .init(type: .string, description: "Timezone used for formatting."),
                    "secondsFromGMT": .init(type: .integer, description: "Offset from GMT at this instant."),
                    "calendarIdentifier": .init(type: .string, description: "Calendar identifier used by the device."),
                    "localeIdentifier": .init(type: .string, description: "Current locale identifier."),
                ],
                required: ["iso8601", "unixTime", "timeZoneIdentifier", "secondsFromGMT", "calendarIdentifier", "localeIdentifier"]
            ),
            permissions: [.localComputation],
            sideEffect: .none,
            networkPolicy: .noNetwork,
            timeoutSeconds: 2,
            explanationRequired: false
        ) { input in
            let date = now()
            let timeZone = DateToolSupport.timeZone(from: input.timeZone)
            let formatter = DateToolSupport.isoFormatter(timeZone: timeZone)
            return TimeNowOutput(
                iso8601: formatter.string(from: date),
                unixTime: date.timeIntervalSince1970,
                timeZoneIdentifier: timeZone.identifier,
                secondsFromGMT: timeZone.secondsFromGMT(for: date),
                calendarIdentifier: Calendar.current.identifier.debugDescription,
                localeIdentifier: Locale.current.identifier
            )
        }
    }
}

public struct DateCalculateInput: ToolInput, Equatable {
    public let operation: String
    public let date: String?
    public let endDate: String?
    public let amount: Int?
    public let unit: String?
    public let weekday: String?
    public let includeToday: Bool?
    public let timeZone: String?

    public init(
        operation: String,
        date: String? = nil,
        endDate: String? = nil,
        amount: Int? = nil,
        unit: String? = nil,
        weekday: String? = nil,
        includeToday: Bool? = nil,
        timeZone: String? = nil
    ) {
        self.operation = operation
        self.date = date
        self.endDate = endDate
        self.amount = amount
        self.unit = unit
        self.weekday = weekday
        self.includeToday = includeToday
        self.timeZone = timeZone
    }
}

public struct DateCalculateOutput: ToolOutput, Equatable {
    public let operation: String
    public let resultISO8601: String?
    public let resultDate: String?
    public let durationSeconds: Double?
    public let componentsJSON: String
    public let timeZoneIdentifier: String
    public let summary: String

    public init(
        operation: String,
        resultISO8601: String?,
        resultDate: String?,
        durationSeconds: Double?,
        componentsJSON: String,
        timeZoneIdentifier: String,
        summary: String
    ) {
        self.operation = operation
        self.resultISO8601 = resultISO8601
        self.resultDate = resultDate
        self.durationSeconds = durationSeconds
        self.componentsJSON = componentsJSON
        self.timeZoneIdentifier = timeZoneIdentifier
        self.summary = summary
    }
}

public enum DateCalculateTool {
    public static let name = "date.calculate"

    public static func spec(now: @escaping @Sendable () -> Date = Date.init) throws -> ToolSpec<DateCalculateInput, DateCalculateOutput> {
        try ToolSpec(
            name: name,
            description: "Perform deterministic date math: add/subtract units, find date differences, resolve weekdays, and compute start or end boundaries.",
            inputSchema: ToolIOSchema(
                properties: [
                    "operation": .init(type: .string, description: "One of add, difference, nextWeekday, startOf, or endOf."),
                    "date": .init(type: .string, description: "Base date as ISO-8601, yyyy-MM-dd, now, today, tomorrow, or yesterday. Defaults to now."),
                    "endDate": .init(type: .string, description: "End date for difference operations."),
                    "amount": .init(type: .integer, description: "Integer amount for add operations. Use negative values to subtract."),
                    "unit": .init(type: .string, description: "second, minute, hour, day, week, month, or year. For boundaries, use day, week, month, or year."),
                    "weekday": .init(type: .string, description: "Weekday name or number for nextWeekday, such as Friday or 6."),
                    "includeToday": .init(type: .boolean, description: "For nextWeekday, allow returning the base date if it already matches."),
                    "timeZone": .init(type: .string, description: "Optional IANA timezone identifier. Defaults to the device timezone."),
                ],
                required: ["operation"]
            ),
            outputSchema: ToolIOSchema(
                properties: [
                    "operation": .init(type: .string, description: "Operation that was run."),
                    "resultISO8601": .init(type: .string, description: "Result date-time when the operation produces a date."),
                    "resultDate": .init(type: .string, description: "Result calendar date in yyyy-MM-dd form when available."),
                    "durationSeconds": .init(type: .number, description: "Total seconds for difference operations."),
                    "componentsJSON": .init(type: .string, description: "Serialized date components such as years, months, days, hours, minutes, and seconds."),
                    "timeZoneIdentifier": .init(type: .string, description: "Timezone used for calculation."),
                    "summary": .init(type: .string, description: "Human-readable calculation summary."),
                ],
                required: ["operation", "componentsJSON", "timeZoneIdentifier", "summary"]
            ),
            permissions: [.localComputation],
            sideEffect: .none,
            networkPolicy: .noNetwork,
            timeoutSeconds: 2,
            explanationRequired: false
        ) { input in
            try DateToolSupport.calculate(input: input, now: now())
        }
    }
}

private enum DateToolSupport {
    static func timeZone(from identifier: String?) -> TimeZone {
        guard let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty,
              let timeZone = TimeZone(identifier: identifier)
        else {
            return .current
        }
        return timeZone
    }

    static func isoFormatter(timeZone: TimeZone) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func calculate(input: DateCalculateInput, now: Date) throws -> DateCalculateOutput {
        let timeZone = timeZone(from: input.timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let operation = input.operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let baseDate = try parseDate(input.date, now: now, calendar: calendar, timeZone: timeZone)

        switch operation {
        case "add":
            return try add(input: input, baseDate: baseDate, calendar: calendar, timeZone: timeZone)
        case "difference":
            return try difference(input: input, baseDate: baseDate, now: now, calendar: calendar, timeZone: timeZone)
        case "nextweekday", "next_weekday":
            return try nextWeekday(input: input, baseDate: baseDate, calendar: calendar, timeZone: timeZone)
        case "startof", "start_of":
            return try boundary(input: input, baseDate: baseDate, calendar: calendar, timeZone: timeZone, end: false)
        case "endof", "end_of":
            return try boundary(input: input, baseDate: baseDate, calendar: calendar, timeZone: timeZone, end: true)
        default:
            throw AgentError.invalidToolArguments("date.calculate operation must be add, difference, nextWeekday, startOf, or endOf.")
        }
    }

    private static func add(
        input: DateCalculateInput,
        baseDate: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) throws -> DateCalculateOutput {
        let amount = input.amount ?? 0
        let component = try calendarComponent(from: input.unit, allowBoundaryUnitsOnly: false)
        guard let result = calendar.date(byAdding: component, value: amount, to: baseDate) else {
            throw AgentError.invalidToolArguments("date.calculate could not add \(amount) \(input.unit ?? "unit").")
        }
        let components = [componentName(component): amount]
        return output(
            operation: "add",
            result: result,
            durationSeconds: nil,
            components: components,
            calendar: calendar,
            timeZone: timeZone,
            summary: "Added \(amount) \(componentName(component)) to \(dateOnly(baseDate, calendar: calendar))."
        )
    }

    private static func difference(
        input: DateCalculateInput,
        baseDate: Date,
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) throws -> DateCalculateOutput {
        let endDate = try parseDate(input.endDate, now: now, calendar: calendar, timeZone: timeZone)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: baseDate, to: endDate)
        let componentValues = [
            "years": components.year ?? 0,
            "months": components.month ?? 0,
            "days": components.day ?? 0,
            "hours": components.hour ?? 0,
            "minutes": components.minute ?? 0,
            "seconds": components.second ?? 0,
        ]
        let seconds = endDate.timeIntervalSince(baseDate)
        return output(
            operation: "difference",
            result: nil,
            durationSeconds: seconds,
            components: componentValues,
            calendar: calendar,
            timeZone: timeZone,
            summary: "Difference from \(dateOnly(baseDate, calendar: calendar)) to \(dateOnly(endDate, calendar: calendar))."
        )
    }

    private static func nextWeekday(
        input: DateCalculateInput,
        baseDate: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) throws -> DateCalculateOutput {
        let targetWeekday = try weekdayNumber(from: input.weekday)
        let current = calendar.component(.weekday, from: baseDate)
        var daysToAdd = (targetWeekday - current + 7) % 7
        if daysToAdd == 0 && input.includeToday != true {
            daysToAdd = 7
        }
        guard let result = calendar.date(byAdding: .day, value: daysToAdd, to: calendar.startOfDay(for: baseDate)) else {
            throw AgentError.invalidToolArguments("date.calculate could not resolve the requested weekday.")
        }
        return output(
            operation: "nextWeekday",
            result: result,
            durationSeconds: nil,
            components: ["days": daysToAdd, "weekday": targetWeekday],
            calendar: calendar,
            timeZone: timeZone,
            summary: "Resolved next \(weekdayName(targetWeekday)) from \(dateOnly(baseDate, calendar: calendar))."
        )
    }

    private static func boundary(
        input: DateCalculateInput,
        baseDate: Date,
        calendar: Calendar,
        timeZone: TimeZone,
        end: Bool
    ) throws -> DateCalculateOutput {
        let component = try calendarComponent(from: input.unit, allowBoundaryUnitsOnly: true)
        let intervalComponent: Calendar.Component = component == .weekOfYear ? .weekOfYear : component
        guard let interval = calendar.dateInterval(of: intervalComponent, for: baseDate) else {
            throw AgentError.invalidToolArguments("date.calculate could not compute boundary for \(input.unit ?? "unit").")
        }
        let result = end ? interval.end.addingTimeInterval(-0.001) : interval.start
        return output(
            operation: end ? "endOf" : "startOf",
            result: result,
            durationSeconds: nil,
            components: [componentName(component): 1],
            calendar: calendar,
            timeZone: timeZone,
            summary: "\(end ? "End" : "Start") of \(componentName(component)) containing \(dateOnly(baseDate, calendar: calendar))."
        )
    }

    private static func output(
        operation: String,
        result: Date?,
        durationSeconds: Double?,
        components: [String: Int],
        calendar: Calendar,
        timeZone: TimeZone,
        summary: String
    ) -> DateCalculateOutput {
        let formatter = isoFormatter(timeZone: timeZone)
        let componentsJSON = (try? String(decoding: JSONEncoder().encode(components), as: UTF8.self)) ?? "{}"
        return DateCalculateOutput(
            operation: operation,
            resultISO8601: result.map(formatter.string(from:)),
            resultDate: result.map { dateOnly($0, calendar: calendar) },
            durationSeconds: durationSeconds,
            componentsJSON: componentsJSON,
            timeZoneIdentifier: timeZone.identifier,
            summary: summary
        )
    }

    private static func parseDate(_ rawValue: String?, now: Date, calendar: Calendar, timeZone: TimeZone) throws -> Date {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return now }
        switch value.lowercased() {
        case "now":
            return now
        case "today":
            return calendar.startOfDay(for: now)
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        case "yesterday":
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        default:
            break
        }

        let fractional = isoFormatter(timeZone: timeZone)
        if let parsed = fractional.date(from: value) {
            return parsed
        }
        let internet = ISO8601DateFormatter()
        internet.timeZone = timeZone
        internet.formatOptions = [.withInternetDateTime]
        if let parsed = internet.date(from: value) {
            return parsed
        }

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = timeZone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let parsed = dateFormatter.date(from: value) {
            return parsed
        }

        throw AgentError.invalidToolArguments("date.calculate could not parse date '\(value)'. Use ISO-8601, yyyy-MM-dd, now, today, tomorrow, or yesterday.")
    }

    private static func calendarComponent(from rawUnit: String?, allowBoundaryUnitsOnly: Bool) throws -> Calendar.Component {
        let unit = rawUnit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch unit {
        case "second", "seconds":
            if allowBoundaryUnitsOnly { break }
            return .second
        case "minute", "minutes":
            if allowBoundaryUnitsOnly { break }
            return .minute
        case "hour", "hours":
            if allowBoundaryUnitsOnly { break }
            return .hour
        case "day", "days":
            return .day
        case "week", "weeks":
            return .weekOfYear
        case "month", "months":
            return .month
        case "year", "years":
            return .year
        default:
            break
        }
        throw AgentError.invalidToolArguments(
            allowBoundaryUnitsOnly
                ? "date.calculate boundary unit must be day, week, month, or year."
                : "date.calculate unit must be second, minute, hour, day, week, month, or year."
        )
    }

    private static func componentName(_ component: Calendar.Component) -> String {
        switch component {
        case .second: "seconds"
        case .minute: "minutes"
        case .hour: "hours"
        case .day: "days"
        case .weekOfYear: "weeks"
        case .month: "months"
        case .year: "years"
        default: "units"
        }
    }

    private static func weekdayNumber(from rawWeekday: String?) throws -> Int {
        guard let weekday = rawWeekday?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !weekday.isEmpty
        else {
            throw AgentError.invalidToolArguments("date.calculate nextWeekday requires weekday.")
        }
        if let numeric = Int(weekday), (1...7).contains(numeric) {
            return numeric
        }
        let names = [
            "sunday": 1, "sun": 1,
            "monday": 2, "mon": 2,
            "tuesday": 3, "tue": 3, "tues": 3,
            "wednesday": 4, "wed": 4,
            "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
            "friday": 6, "fri": 6,
            "saturday": 7, "sat": 7,
        ]
        guard let value = names[weekday] else {
            throw AgentError.invalidToolArguments("date.calculate weekday must be a weekday name or 1...7 where 1 is Sunday.")
        }
        return value
    }

    private static func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: "Sunday"
        case 2: "Monday"
        case 3: "Tuesday"
        case 4: "Wednesday"
        case 5: "Thursday"
        case 6: "Friday"
        case 7: "Saturday"
        default: "weekday"
        }
    }

    private static func dateOnly(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
