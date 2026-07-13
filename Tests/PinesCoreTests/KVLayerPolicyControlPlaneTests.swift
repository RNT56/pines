import Foundation
import PinesCore
import Testing

@Suite("KV layer policy control plane")
struct KVLayerPolicyControlPlaneTests {
    @Test
    func quantizationProfileRoundTripsKVLayerPolicyAndMetadataValues() throws {
        let policy = KVLayerPolicy(
            defaultCodec: .turboQuant(
                preset: .turbo4v2,
                valueBits: 4,
                groupSize: 64,
                backend: .metalPolarQJL
            ),
            rules: [
                KVLayerRule(layerIndex: 3, codec: .affineK8V4),
                KVLayerRule(layerIndex: 7, codec: .rawFP16),
            ]
        )
        let profile = QuantizationProfile(
            kvCacheStrategy: .turboQuant,
            turboQuantKVLayerPolicy: policy
        )

        let decoded = try JSONDecoder().decode(
            QuantizationProfile.self,
            from: JSONEncoder().encode(profile)
        )

        #expect(decoded.turboQuantKVLayerPolicy == policy)
        #expect(policy.stableHash == decoded.turboQuantKVLayerPolicy?.stableHash)
        #expect(policy.summary().contains("3:affineK8V4"))
        #expect(LocalProviderMetadataKeys.turboQuantKVLayerPolicyJSON.contains("kv_layer_policy"))
        #expect(LocalProviderMetadataKeys.turboQuantKVLayerPolicyHash.contains("hash"))
        #expect(LocalProviderMetadataKeys.turboQuantKVLayerPolicySummary.contains("summary"))
    }
}
