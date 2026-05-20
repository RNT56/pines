import Foundation
import PinesCore
#if canImport(StoreKit)
import StoreKit
#endif

struct PinesProEntitlementConfiguration: Hashable, Sendable {
    var productIDs: [String]

    static func bundleDefault(bundle: Bundle = .main) -> Self {
        let rawIDs = bundle.object(forInfoDictionaryKey: "PINES_PRO_PRODUCT_IDS") as? String ?? ""
        let productIDs = rawIDs
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return .init(productIDs: productIDs)
    }
}

struct PinesProEntitlementService: Sendable {
    var configuration: PinesProEntitlementConfiguration

    init(configuration: PinesProEntitlementConfiguration = .bundleDefault()) {
        self.configuration = configuration
    }

    var isConfigured: Bool {
        !configuration.productIDs.isEmpty
    }

    func currentStatus() async -> ProEntitlementStatus {
        guard isConfigured else { return .inactive }
        #if canImport(StoreKit)
        let productIDs = Set(configuration.productIDs)
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  productIDs.contains(transaction.productID)
            else {
                continue
            }
            if transaction.revocationDate != nil {
                return .revoked
            }
            if let expirationDate = transaction.expirationDate, expirationDate < Date() {
                return .expired
            }
            return .active
        }
        return .inactive
        #else
        return .inactive
        #endif
    }

    func verifiedTransactionID() async -> String? {
        guard isConfigured else { return nil }
        #if canImport(StoreKit)
        let productIDs = Set(configuration.productIDs)
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil
            else {
                continue
            }
            return String(transaction.id)
        }
        return nil
        #else
        return nil
        #endif
    }
}
