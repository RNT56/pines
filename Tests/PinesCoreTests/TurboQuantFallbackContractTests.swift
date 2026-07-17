import PinesCore
import Testing

@Suite("TurboQuant fallback contract")
struct TurboQuantFallbackContractTests {
    @Test
    func defaultContractsMatchModePolicy() {
        let fastest = TurboQuantFallbackContract.productDefault(for: .fastest)
        #expect(fastest.allowPackedFallback)
        #expect(!fastest.allowDecodedLayerLocalFallback)
        #expect(!fastest.allowFullDecodedFallback)
        #expect(fastest.allowShorterContextRetry)
        #expect(!fastest.allowCloudRetry)

        let balanced = TurboQuantFallbackContract.productDefault(for: .balanced)
        #expect(balanced.allowPackedFallback)
        #expect(balanced.allowDecodedLayerLocalFallback)
        #expect(!balanced.allowFullDecodedFallback)
        #expect(balanced.allowShorterContextRetry)
        #expect(!balanced.allowCloudRetry)

        let maxContext = TurboQuantFallbackContract.productDefault(for: .maxContext)
        #expect(!maxContext.allowPackedFallback)
        #expect(!maxContext.allowDecodedLayerLocalFallback)
        #expect(!maxContext.allowFullDecodedFallback)
        #expect(maxContext.allowShorterContextRetry)
        #expect(!maxContext.allowCloudRetry)
        #expect(maxContext.failIfCompressedPathUnavailable)

        let batterySaver = TurboQuantFallbackContract.productDefault(for: .batterySaver)
        #expect(!batterySaver.allowPackedFallback)
        #expect(!batterySaver.allowDecodedLayerLocalFallback)
        #expect(!batterySaver.allowFullDecodedFallback)
        #expect(batterySaver.allowShorterContextRetry)
        #expect(!batterySaver.allowCloudRetry)
    }

    @Test
    func balancedNeverDowngradesToMaxContext() {
        let contract = TurboQuantFallbackContract.productDefault(for: .balanced)

        let modes = contract.shorterContextDowngradePath().map(\.mode)

        #expect(modes == [.balanced, .batterySaver])
        #expect(!modes.contains(.maxContext))
        #expect(contract.shorterContextDowngradePath().allSatisfy { !$0.downgradeReason.isEmpty })
        #expect(contract.shorterContextDowngradePath().allSatisfy { !$0.userFacingMessage.isEmpty })
    }

    @Test
    func maxContextShorterCanDowngradeToBalancedShorter() {
        let contract = TurboQuantFallbackContract.productDefault(for: .maxContext)

        let path = contract.shorterContextDowngradePath()

        #expect(path.map(\.mode) == [.maxContext, .balanced, .batterySaver])
        #expect(path.allSatisfy { $0.requiresShorterContext })
        #expect(path.contains { $0.mode == .balanced && $0.reason == .balancedShorterContext })
    }

    @Test
    func cloudRetryRequiresExplicitPolicy() {
        let productDefault = TurboQuantFallbackContract.productDefault(for: .balanced)
        let explicitlyAllowed = TurboQuantFallbackContract.productDefault(
            for: .balanced,
            allowCloudRetry: true
        )

        #expect(!productDefault.allowCloudRetry)
        #expect(explicitlyAllowed.allowCloudRetry)
    }

    @Test
    func fullDecodedFallbackRequiresExplicitBudget() {
        var contract = TurboQuantFallbackContract.productDefault(for: .balanced)
        #expect(!contract.permitsFullDecodedFallback(budgetedDecodedFallbackBytes: 1))

        contract.allowFullDecodedFallback = true
        contract.reserveBytes = 1_024

        #expect(!contract.permitsFullDecodedFallback(budgetedDecodedFallbackBytes: 0))
        #expect(!contract.permitsFullDecodedFallback(budgetedDecodedFallbackBytes: 2_048))
        #expect(contract.permitsFullDecodedFallback(budgetedDecodedFallbackBytes: 1_024))
    }

    @Test
    func hashesTrackPolicyAndReserveChanges() {
        let baseline = TurboQuantFallbackContract.productDefault(for: .balanced, reserveBytes: 1_024)
        var flagChanged = baseline
        flagChanged.allowDecodedLayerLocalFallback = false

        var reserveChanged = baseline
        reserveChanged.reserveBytes = 2_048

        #expect(flagChanged.contractHash != baseline.contractHash)
        #expect(flagChanged.policyHash != baseline.policyHash)
        #expect(reserveChanged.contractHash != baseline.contractHash)
        #expect(reserveChanged.policyHash == baseline.policyHash)
    }

    @Test
    func hashesAreStableSha256HexStrings() {
        let first = TurboQuantFallbackContract.productDefault(for: .balanced)
        let second = TurboQuantFallbackContract.productDefault(for: .balanced)

        #expect(first.contractHash == second.contractHash)
        #expect(first.policyHash == second.policyHash)
        #expect(first.contractHash.count == 64)
        #expect(first.policyHash.count == 64)
        #expect(first.contractHash.allSatisfy { $0.isHexDigit })
        #expect(first.policyHash.allSatisfy { $0.isHexDigit })
    }
}
