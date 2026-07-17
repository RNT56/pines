import Foundation
import Testing
@testable import PinesCore

@Suite("Persistence data lifecycle")
struct PersistenceDataLifecycleTests {
    @Test func durableTableCatalogCoversEveryCreatedApplicationTable() {
        let catalog = Set(PinesDatabaseSchema.durableUserTableNames)
        let createdTables = Set(
            PinesDatabaseSchema.migrations
                .flatMap(\.sql)
                .compactMap(Self.createdTableName)
        )

        #expect(PinesDatabaseSchema.durableUserTableNames.count == catalog.count)
        #expect(createdTables == catalog)
    }

    private static func createdTableName(in statement: String) -> String? {
        let prefix = "CREATE TABLE IF NOT EXISTS "
        guard let range = statement.range(of: prefix, options: .caseInsensitive) else {
            return nil
        }
        let suffix = statement[range.upperBound...]
        let rawName = suffix.prefix { character in
            !character.isWhitespace && character != "("
        }
        let name = rawName.trimmingCharacters(in: CharacterSet(charactersIn: "`\"[]"))
        return name.isEmpty ? nil : name
    }
}
