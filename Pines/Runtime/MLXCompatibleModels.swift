import Foundation

#if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXNN)
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN

struct PinesLlama4Configuration: Decodable, Sendable {
    var textConfig: PinesLlama4TextConfiguration

    enum CodingKeys: String, CodingKey {
        case textConfig = "text_config"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let textConfig = try container.decodeIfPresent(PinesLlama4TextConfiguration.self, forKey: .textConfig) {
            self.textConfig = textConfig
        } else {
            self.textConfig = try PinesLlama4TextConfiguration(from: decoder)
        }
    }
}

struct PinesLlama4TextConfiguration: Decodable, Sendable {
    var hiddenSize: Int
    var hiddenLayers: Int
    var intermediateSize: Int
    var intermediateSizeMLP: Int
    var attentionHeads: Int
    var kvHeads: Int
    var headDim: Int
    var rmsNormEps: Float
    var vocabularySize: Int
    var maxPositionEmbeddings: Int
    var ropeTheta: Float
    var ropeScaling: [String: StringOrNumber]?
    var tieWordEmbeddings: Bool
    var attentionBias: Bool
    var numExpertsPerToken: Int
    var numLocalExperts: Int
    var moeLayers: [Int]
    var noRopeLayers: [Bool]
    var useQKNorm: Bool
    var attentionTemperatureTuning: Bool
    var floorScale: Int
    var attentionScale: Float

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case hiddenLayers = "num_hidden_layers"
        case intermediateSize = "intermediate_size"
        case intermediateSizeMLP = "intermediate_size_mlp"
        case attentionHeads = "num_attention_heads"
        case kvHeads = "num_key_value_heads"
        case headDim = "head_dim"
        case rmsNormEps = "rms_norm_eps"
        case vocabularySize = "vocab_size"
        case maxPositionEmbeddings = "max_position_embeddings"
        case ropeTheta = "rope_theta"
        case ropeScaling = "rope_scaling"
        case tieWordEmbeddings = "tie_word_embeddings"
        case attentionBias = "attention_bias"
        case numExpertsPerToken = "num_experts_per_tok"
        case numLocalExperts = "num_local_experts"
        case moeLayers = "moe_layers"
        case interleaveMoELayerStep = "interleave_moe_layer_step"
        case noRopeLayers = "no_rope_layers"
        case noRopeLayerInterval = "no_rope_layer_interval"
        case useQKNorm = "use_qk_norm"
        case attentionTemperatureTuning = "attn_temperature_tuning"
        case floorScale = "floor_scale"
        case attentionScale = "attn_scale"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        hiddenSize = try container.decode(Int.self, forKey: .hiddenSize)
        hiddenLayers = try container.decode(Int.self, forKey: .hiddenLayers)
        intermediateSize = try container.decode(Int.self, forKey: .intermediateSize)
        intermediateSizeMLP = try container.decodeIfPresent(Int.self, forKey: .intermediateSizeMLP)
            ?? intermediateSize
        attentionHeads = try container.decode(Int.self, forKey: .attentionHeads)
        kvHeads = try container.decodeIfPresent(Int.self, forKey: .kvHeads) ?? attentionHeads
        headDim = try container.decodeIfPresent(Int.self, forKey: .headDim) ?? hiddenSize / attentionHeads
        rmsNormEps = try container.decode(Float.self, forKey: .rmsNormEps)
        vocabularySize = try container.decode(Int.self, forKey: .vocabularySize)
        maxPositionEmbeddings = try container.decodeIfPresent(Int.self, forKey: .maxPositionEmbeddings)
            ?? 131_072
        ropeTheta = try container.decodeIfPresent(Float.self, forKey: .ropeTheta) ?? 500_000
        ropeScaling = try container.decodeIfPresent([String: StringOrNumber].self, forKey: .ropeScaling)
        tieWordEmbeddings = try container.decodeIfPresent(Bool.self, forKey: .tieWordEmbeddings) ?? false
        attentionBias = try container.decodeIfPresent(Bool.self, forKey: .attentionBias) ?? false
        numExpertsPerToken = try container.decodeIfPresent(Int.self, forKey: .numExpertsPerToken) ?? 1
        numLocalExperts = try container.decodeIfPresent(Int.self, forKey: .numLocalExperts) ?? 16
        useQKNorm = try container.decodeIfPresent(Bool.self, forKey: .useQKNorm) ?? true
        attentionTemperatureTuning = try container.decodeIfPresent(Bool.self, forKey: .attentionTemperatureTuning)
            ?? true
        floorScale = try container.decodeIfPresent(Int.self, forKey: .floorScale) ?? 8192
        attentionScale = try container.decodeIfPresent(Float.self, forKey: .attentionScale) ?? 0.1

        let interleaveStep = try container.decodeIfPresent(Int.self, forKey: .interleaveMoELayerStep) ?? 1
        moeLayers = try container.decodeIfPresent([Int].self, forKey: .moeLayers)
            ?? Array(stride(from: max(interleaveStep - 1, 0), to: hiddenLayers, by: max(interleaveStep, 1)))

        if let noRopeLayerFlags = try container.decodeIfPresent([Int].self, forKey: .noRopeLayers) {
            noRopeLayers = noRopeLayerFlags.map { $0 != 0 }
        } else {
            let interval = try container.decodeIfPresent(Int.self, forKey: .noRopeLayerInterval) ?? 4
            noRopeLayers = (0 ..< hiddenLayers).map { ($0 + 1) % max(interval, 1) != 0 }
        }
    }
}

private final class PinesLlama4L2Norm: Module, UnaryLayer {
    private let eps: Float

    init(eps: Float) {
        self.eps = eps
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        x * rsqrt(mean(x.square(), axis: -1, keepDims: true) + eps)
    }
}

private final class PinesLlama4MLP: Module, UnaryLayer {
    @ModuleInfo(key: "gate_proj") var gate: Linear
    @ModuleInfo(key: "down_proj") var down: Linear
    @ModuleInfo(key: "up_proj") var up: Linear

    init(hiddenSize: Int, intermediateSize: Int) {
        _gate.wrappedValue = Linear(hiddenSize, intermediateSize, bias: false)
        _down.wrappedValue = Linear(intermediateSize, hiddenSize, bias: false)
        _up.wrappedValue = Linear(hiddenSize, intermediateSize, bias: false)
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        down(silu(gate(x)) * up(x))
    }
}

private final class PinesLlama4Router: Module {
    let topK: Int

    @ParameterInfo(key: "weight") var weight: MLXArray

    init(hiddenSize: Int, numExperts: Int, topK: Int) {
        self.topK = topK
        self._weight.wrappedValue = zeros([numExperts, hiddenSize])
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> (MLXArray, MLXArray) {
        let logits = matmul(x, weight.T)
        let k = max(topK, 1)
        let kth = logits.dim(-1) - k
        let indices = argPartition(logits, kth: kth, axis: -1)[.ellipsis, kth...]
        let scores = sigmoid(takeAlong(logits, indices, axis: -1))
        return (indices, scores)
    }
}

private final class PinesLlama4FeedForward: Module, UnaryLayer {
    private let isMoELayer: Bool

    @ModuleInfo(key: "gate_proj") var denseGate: Linear?
    @ModuleInfo(key: "down_proj") var denseDown: Linear?
    @ModuleInfo(key: "up_proj") var denseUp: Linear?
    @ModuleInfo(key: "router") var router: PinesLlama4Router?
    @ModuleInfo(key: "switch_mlp") var switchMLP: SwitchGLU?
    @ModuleInfo(key: "shared_expert") var sharedExpert: PinesLlama4MLP?

    init(_ config: PinesLlama4TextConfiguration, isMoELayer: Bool) {
        self.isMoELayer = isMoELayer
        if isMoELayer {
            _router.wrappedValue = PinesLlama4Router(
                hiddenSize: config.hiddenSize,
                numExperts: config.numLocalExperts,
                topK: config.numExpertsPerToken
            )
            _switchMLP.wrappedValue = SwitchGLU(
                inputDims: config.hiddenSize,
                hiddenDims: config.intermediateSize,
                numExperts: config.numLocalExperts
            )
            _sharedExpert.wrappedValue = PinesLlama4MLP(
                hiddenSize: config.hiddenSize,
                intermediateSize: config.intermediateSize
            )
        } else {
            _denseGate.wrappedValue = Linear(config.hiddenSize, config.intermediateSizeMLP, bias: false)
            _denseDown.wrappedValue = Linear(config.intermediateSizeMLP, config.hiddenSize, bias: false)
            _denseUp.wrappedValue = Linear(config.hiddenSize, config.intermediateSizeMLP, bias: false)
        }
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        if isMoELayer {
            guard let router, let switchMLP, let sharedExpert else {
                return x
            }
            let (indices, scores) = router(x)
            let routed = switchMLP(x, indices)
            let combined = (routed * scores[.ellipsis, .newAxis]).sum(axis: -2)
            return combined + sharedExpert(x)
        }

        guard let denseGate, let denseDown, let denseUp else {
            return x
        }
        return denseDown(silu(denseGate(x)) * denseUp(x))
    }
}

private final class PinesLlama4Attention: Module {
    private let config: PinesLlama4TextConfiguration
    private let layerIndex: Int
    private let scale: Float
    private let useRoPE: Bool
    private let rope: RoPELayer
    private let qkNorm: PinesLlama4L2Norm?

    @ModuleInfo(key: "q_proj") var wq: Linear
    @ModuleInfo(key: "k_proj") var wk: Linear
    @ModuleInfo(key: "v_proj") var wv: Linear
    @ModuleInfo(key: "o_proj") var wo: Linear

    init(_ config: PinesLlama4TextConfiguration, layerIndex: Int) {
        self.config = config
        self.layerIndex = layerIndex
        self.scale = pow(Float(config.headDim), -0.5)
        self.useRoPE = layerIndex < config.noRopeLayers.count ? config.noRopeLayers[layerIndex] : true
        self.rope = initializeRope(
            dims: config.headDim,
            base: config.ropeTheta,
            traditional: false,
            scalingConfig: config.ropeScaling,
            maxPositionEmbeddings: config.maxPositionEmbeddings
        )
        self.qkNorm = config.useQKNorm && useRoPE ? PinesLlama4L2Norm(eps: config.rmsNormEps) : nil
        _wq.wrappedValue = Linear(
            config.hiddenSize,
            config.attentionHeads * config.headDim,
            bias: config.attentionBias
        )
        _wk.wrappedValue = Linear(
            config.hiddenSize,
            config.kvHeads * config.headDim,
            bias: config.attentionBias
        )
        _wv.wrappedValue = Linear(
            config.hiddenSize,
            config.kvHeads * config.headDim,
            bias: config.attentionBias
        )
        _wo.wrappedValue = Linear(
            config.attentionHeads * config.headDim,
            config.hiddenSize,
            bias: config.attentionBias
        )
        super.init()
    }

    func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache?
    ) -> MLXArray {
        let (batchSize, length) = (x.dim(0), x.dim(1))
        var queries = wq(x)
            .reshaped(batchSize, length, config.attentionHeads, config.headDim)
            .transposed(0, 2, 1, 3)
        var keys = wk(x)
            .reshaped(batchSize, length, config.kvHeads, config.headDim)
            .transposed(0, 2, 1, 3)
        let values = wv(x)
            .reshaped(batchSize, length, config.kvHeads, config.headDim)
            .transposed(0, 2, 1, 3)

        if useRoPE {
            let offset = cache?.ropeOffset
            queries = applyRotaryPosition(rope, to: queries, offset: offset)
            keys = applyRotaryPosition(rope, to: keys, offset: offset)
        } else if config.attentionTemperatureTuning {
            let offset = cache?.offset ?? 0
            let positions = MLXArray(offset ..< offset + length).asType(x.dtype)
            let scales = log(positions.floorDivide(config.floorScale) + 1) * config.attentionScale + 1
            queries = queries * scales.reshaped(1, 1, length, 1)
        }

        if let qkNorm {
            queries = qkNorm(queries)
            keys = qkNorm(keys)
        }

        let output = attentionWithCacheUpdate(
            queries: queries,
            keys: keys,
            values: values,
            cache: cache,
            scale: scale,
            mask: mask
        )
        .transposed(0, 2, 1, 3)
        .reshaped(batchSize, length, -1)

        return wo(output)
    }
}

private final class PinesLlama4DecoderLayer: Module {
    @ModuleInfo(key: "self_attn") var selfAttention: PinesLlama4Attention
    @ModuleInfo(key: "feed_forward") var feedForward: PinesLlama4FeedForward
    @ModuleInfo(key: "input_layernorm") var inputLayerNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayerNorm: RMSNorm

    init(_ config: PinesLlama4TextConfiguration, layerIndex: Int) {
        _selfAttention.wrappedValue = PinesLlama4Attention(config, layerIndex: layerIndex)
        _feedForward.wrappedValue = PinesLlama4FeedForward(
            config,
            isMoELayer: config.moeLayers.contains(layerIndex)
        )
        _inputLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        _postAttentionLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        super.init()
    }

    func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache?
    ) -> MLXArray {
        let h = x + selfAttention(inputLayerNorm(x), mask: mask, cache: cache)
        return h + feedForward(postAttentionLayerNorm(h))
    }
}

fileprivate final class PinesLlama4TextModelInner: Module {
    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo(key: "layers") var layers: [PinesLlama4DecoderLayer]
    @ModuleInfo(key: "norm") var norm: RMSNorm

    init(_ config: PinesLlama4TextConfiguration) {
        _embedTokens.wrappedValue = Embedding(
            embeddingCount: config.vocabularySize,
            dimensions: config.hiddenSize
        )
        _layers.wrappedValue = (0 ..< config.hiddenLayers).map {
            PinesLlama4DecoderLayer(config, layerIndex: $0)
        }
        _norm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        super.init()
    }

    func callAsFunction(_ inputs: MLXArray, cache: [KVCache]? = nil) -> MLXArray {
        var h = embedTokens(inputs)
        let mask = createAttentionMask(h: h, cache: cache?.first)
        for (index, layer) in layers.enumerated() {
            h = layer(h, mask: mask, cache: cache?[index])
        }
        return norm(h)
    }
}

final class PinesLlama4TextModel: Module, LLMModel, KVCacheDimensionProvider {
    let configuration: PinesLlama4TextConfiguration
    private let model: PinesLlama4TextModelInner
    let vocabularySize: Int
    let kvHeads: [Int]

    @ModuleInfo(key: "lm_head") var lmHead: Linear?

    init(_ configuration: PinesLlama4TextConfiguration) {
        self.configuration = configuration
        self.vocabularySize = configuration.vocabularySize
        self.kvHeads = (0 ..< configuration.hiddenLayers).map { _ in configuration.kvHeads }
        self.model = PinesLlama4TextModelInner(configuration)
        if !configuration.tieWordEmbeddings {
            _lmHead.wrappedValue = Linear(configuration.hiddenSize, configuration.vocabularySize, bias: false)
        }
        super.init()
    }

    func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
        let out = model(inputs, cache: cache)
        if let lmHead {
            return lmHead(out)
        }
        return model.embedTokens.asLinear(out)
    }

    func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        sanitizeLlama4TextWeights(weights, layerCount: configuration.hiddenLayers)
    }

    var loraLayers: [Module] {
        model.layers
    }
}

final class PinesLlama4Model: Module, LLMModel, KVCacheDimensionProvider {
    @ModuleInfo(key: "language_model") var languageModel: PinesLlama4TextModel

    init(_ configuration: PinesLlama4Configuration) {
        _languageModel.wrappedValue = PinesLlama4TextModel(configuration.textConfig)
        super.init()
    }

    var kvHeads: [Int] {
        languageModel.kvHeads
    }

    func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
        languageModel(inputs, cache: cache)
    }

    func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var scopedWeights = [String: MLXArray]()
        for (key, value) in weights {
            if key.hasPrefix("vision_model.")
                || key.hasPrefix("vision_tower.")
                || key.hasPrefix("multi_modal_projector.")
            {
                continue
            }

            if key.hasPrefix("language_model.") {
                scopedWeights[key] = value
            } else {
                scopedWeights["language_model.\(key)"] = value
            }
        }

        return sanitizeLlama4TextWeights(
            scopedWeights,
            layerCount: languageModel.configuration.hiddenLayers,
            prefix: "language_model."
        )
    }

    var loraLayers: [Module] {
        languageModel.loraLayers
    }
}

private func sanitizeLlama4TextWeights(
    _ weights: [String: MLXArray],
    layerCount: Int,
    prefix: String = ""
) -> [String: MLXArray] {
    var newWeights = [String: MLXArray]()
    for (key, value) in weights {
        guard !key.contains("rotary_emb.inv_freq") else { continue }
        newWeights[key] = value
    }

    for layerIndex in 0 ..< layerCount {
        let layerPrefix = "\(prefix)model.layers.\(layerIndex).feed_forward"
        let gateUpKey = "\(layerPrefix).experts.gate_up_proj"
        if let gateUp = newWeights.removeValue(forKey: gateUpKey) {
            let midpoint = gateUp.dim(-2) / 2
            newWeights["\(layerPrefix).switch_mlp.gate_proj.weight"] =
                gateUp[.ellipsis, ..<midpoint, 0...]
            newWeights["\(layerPrefix).switch_mlp.up_proj.weight"] =
                gateUp[.ellipsis, midpoint..., 0...]
        }

        let downKey = "\(layerPrefix).experts.down_proj"
        if let down = newWeights.removeValue(forKey: downKey) {
            newWeights["\(layerPrefix).switch_mlp.down_proj.weight"] = down
        }
    }

    return newWeights
}

struct PinesDeepseekV4Configuration: Decodable, Sendable {
    enum AttentionLayerType: String, Sendable {
        case sliding = "sliding_attention"
        case compressedSparse = "compressed_sparse_attention"
        case heavilyCompressed = "heavily_compressed_attention"
    }

    enum MLPLayerType: String, Sendable {
        case hashMoE = "hash_moe"
        case moe
    }

    var vocabularySize: Int
    var hiddenSize: Int
    var intermediateSize: Int
    var hiddenLayers: Int
    var attentionHeads: Int
    var kvHeads: Int
    var headDim: Int
    var qLoraRank: Int
    var qkRopeHeadDim: Int
    var maxPositionEmbeddings: Int
    var ropeTheta: Float
    var compressRopeTheta: Float
    var ropeScaling: [String: StringOrNumber]?
    var rmsNormEps: Float
    var attentionBias: Bool
    var attentionDropout: Float
    var slidingWindow: Int
    var compressRateCSA: Int
    var compressRateHCA: Int
    var hcMult: Int
    var hcSinkhornIterations: Int
    var hcEps: Float
    var oGroups: Int
    var oLoraRank: Int
    var indexHeads: Int
    var indexHeadDim: Int
    var indexTopK: Int
    var expertsPerToken: Int
    var routedExperts: Int
    var sharedExperts: Int
    var routedScalingFactor: Float
    var scoringFunction: String
    var swigluLimit: Float
    var tieWordEmbeddings: Bool
    var layerTypes: [AttentionLayerType]
    var mlpLayerTypes: [MLPLayerType]

    enum CodingKeys: String, CodingKey {
        case vocabularySize = "vocab_size"
        case hiddenSize = "hidden_size"
        case intermediateSize = "moe_intermediate_size"
        case hiddenLayers = "num_hidden_layers"
        case attentionHeads = "num_attention_heads"
        case kvHeads = "num_key_value_heads"
        case headDim = "head_dim"
        case qLoraRank = "q_lora_rank"
        case qkRopeHeadDim = "qk_rope_head_dim"
        case maxPositionEmbeddings = "max_position_embeddings"
        case ropeTheta = "rope_theta"
        case compressRopeTheta = "compress_rope_theta"
        case ropeScaling = "rope_scaling"
        case rmsNormEps = "rms_norm_eps"
        case attentionBias = "attention_bias"
        case attentionDropout = "attention_dropout"
        case slidingWindow = "sliding_window"
        case compressRates = "compress_rates"
        case compressRateCSA = "compress_rate_csa"
        case compressRateHCA = "compress_rate_hca"
        case compressRatios = "compress_ratios"
        case hcMult = "hc_mult"
        case hcSinkhornIterations = "hc_sinkhorn_iters"
        case hcEps = "hc_eps"
        case oGroups = "o_groups"
        case oLoraRank = "o_lora_rank"
        case indexHeads = "index_n_heads"
        case indexHeadDim = "index_head_dim"
        case indexTopK = "index_topk"
        case expertsPerToken = "num_experts_per_tok"
        case routedExperts = "n_routed_experts"
        case sharedExperts = "n_shared_experts"
        case routedScalingFactor = "routed_scaling_factor"
        case scoringFunction = "scoring_func"
        case swigluLimit = "swiglu_limit"
        case tieWordEmbeddings = "tie_word_embeddings"
        case layerTypes = "layer_types"
        case mlpLayerTypes = "mlp_layer_types"
        case hashLayers = "num_hash_layers"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vocabularySize = try container.decodeIfPresent(Int.self, forKey: .vocabularySize) ?? 129_280
        hiddenSize = try container.decodeIfPresent(Int.self, forKey: .hiddenSize) ?? 4096
        intermediateSize = try container.decodeIfPresent(Int.self, forKey: .intermediateSize) ?? 2048
        hiddenLayers = try container.decodeIfPresent(Int.self, forKey: .hiddenLayers) ?? 43
        attentionHeads = try container.decodeIfPresent(Int.self, forKey: .attentionHeads) ?? 64
        kvHeads = try container.decodeIfPresent(Int.self, forKey: .kvHeads) ?? 1
        headDim = try container.decodeIfPresent(Int.self, forKey: .headDim) ?? 512
        qLoraRank = try container.decodeIfPresent(Int.self, forKey: .qLoraRank) ?? 1024
        qkRopeHeadDim = try container.decodeIfPresent(Int.self, forKey: .qkRopeHeadDim) ?? 64
        maxPositionEmbeddings = try container.decodeIfPresent(Int.self, forKey: .maxPositionEmbeddings)
            ?? 1_048_576
        ropeTheta = try container.decodeIfPresent(Float.self, forKey: .ropeTheta) ?? 10_000
        compressRopeTheta = try container.decodeIfPresent(Float.self, forKey: .compressRopeTheta)
            ?? 160_000
        ropeScaling = try container.decodeIfPresent([String: StringOrNumber].self, forKey: .ropeScaling)
        rmsNormEps = try container.decodeIfPresent(Float.self, forKey: .rmsNormEps) ?? 1.0e-6
        attentionBias = try container.decodeIfPresent(Bool.self, forKey: .attentionBias) ?? false
        attentionDropout = try container.decodeIfPresent(Float.self, forKey: .attentionDropout) ?? 0
        slidingWindow = try container.decodeIfPresent(Int.self, forKey: .slidingWindow) ?? 128

        let compressRates = try container.decodeIfPresent([String: Int].self, forKey: .compressRates)
        compressRateCSA = try container.decodeIfPresent(Int.self, forKey: .compressRateCSA)
            ?? compressRates?["compressed_sparse_attention"] ?? 4
        compressRateHCA = try container.decodeIfPresent(Int.self, forKey: .compressRateHCA)
            ?? compressRates?["heavily_compressed_attention"] ?? 128

        hcMult = try container.decodeIfPresent(Int.self, forKey: .hcMult) ?? 4
        hcSinkhornIterations = try container.decodeIfPresent(Int.self, forKey: .hcSinkhornIterations) ?? 20
        hcEps = try container.decodeIfPresent(Float.self, forKey: .hcEps) ?? 1.0e-6
        oGroups = try container.decodeIfPresent(Int.self, forKey: .oGroups) ?? 8
        oLoraRank = try container.decodeIfPresent(Int.self, forKey: .oLoraRank) ?? 1024
        indexHeads = try container.decodeIfPresent(Int.self, forKey: .indexHeads) ?? 64
        indexHeadDim = try container.decodeIfPresent(Int.self, forKey: .indexHeadDim) ?? 128
        indexTopK = try container.decodeIfPresent(Int.self, forKey: .indexTopK) ?? 512
        expertsPerToken = try container.decodeIfPresent(Int.self, forKey: .expertsPerToken) ?? 6
        routedExperts = try container.decodeIfPresent(Int.self, forKey: .routedExperts) ?? 256
        sharedExperts = try container.decodeIfPresent(Int.self, forKey: .sharedExperts) ?? 1
        routedScalingFactor = try container.decodeIfPresent(Float.self, forKey: .routedScalingFactor) ?? 1.5
        scoringFunction = try container.decodeIfPresent(String.self, forKey: .scoringFunction)
            ?? "sqrtsoftplus"
        swigluLimit = try container.decodeIfPresent(Float.self, forKey: .swigluLimit) ?? 10
        tieWordEmbeddings = try container.decodeIfPresent(Bool.self, forKey: .tieWordEmbeddings) ?? false

        if let explicitLayerTypes = try container.decodeIfPresent([String].self, forKey: .layerTypes) {
            layerTypes = explicitLayerTypes.prefix(hiddenLayers).map {
                AttentionLayerType(rawValue: $0) ?? .heavilyCompressed
            }
        } else if let ratios = try container.decodeIfPresent([Int].self, forKey: .compressRatios) {
            let compressedSparseRate = compressRateCSA
            let heavilyCompressedRate = compressRateHCA
            layerTypes = ratios.prefix(hiddenLayers).map {
                switch $0 {
                case 0: .sliding
                case compressedSparseRate: .compressedSparse
                case heavilyCompressedRate: .heavilyCompressed
                default: .heavilyCompressed
                }
            }
        } else {
            let rest = (0 ..< max(hiddenLayers - 2, 0)).map {
                $0.isMultiple(of: 2) ? AttentionLayerType.heavilyCompressed : .compressedSparse
            }
            layerTypes = Array(repeating: .heavilyCompressed, count: min(hiddenLayers, 2)) + rest
        }
        if layerTypes.count < hiddenLayers {
            layerTypes += Array(repeating: .heavilyCompressed, count: hiddenLayers - layerTypes.count)
        }

        if let explicitMLPTypes = try container.decodeIfPresent([String].self, forKey: .mlpLayerTypes) {
            mlpLayerTypes = explicitMLPTypes.prefix(hiddenLayers).map {
                MLPLayerType(rawValue: $0) ?? .moe
            }
        } else {
            let hashLayers = try container.decodeIfPresent(Int.self, forKey: .hashLayers) ?? 3
            mlpLayerTypes =
                Array(repeating: .hashMoE, count: min(hiddenLayers, hashLayers))
                + Array(repeating: .moe, count: max(0, hiddenLayers - hashLayers))
        }
    }
}

private final class PinesDeepseekV4KVCache: KVCache, CustomDebugStringConvertible {
    let layerType: PinesDeepseekV4Configuration.AttentionLayerType
    let slidingWindow: Int
    var offset: Int = 0

    private var keys: MLXArray?
    private var bufferKV = [String: MLXArray]()
    private var bufferGate = [String: MLXArray]()
    private var compressedKV = [String: MLXArray]()
    private var entryCount = [String: Int]()
    private var overlapKV = [String: MLXArray]()
    private var overlapGate = [String: MLXArray]()

    var maxSize: Int? { slidingWindow }

    init(layerType: PinesDeepseekV4Configuration.AttentionLayerType, slidingWindow: Int) {
        self.layerType = layerType
        self.slidingWindow = slidingWindow
    }

    func update(keys: MLXArray, values: MLXArray) -> (MLXArray, MLXArray) {
        let full = self.keys.map { concatenated([$0, keys], axis: 2) } ?? keys
        let keep = max(slidingWindow - 1, 1)
        if full.dim(2) > keep {
            self.keys = full[.ellipsis, (full.dim(2) - keep)..., 0...]
        } else {
            self.keys = full
        }
        offset += keys.dim(2)
        return (full, full)
    }

    func storeCompressionWeights(
        name: String,
        kv: MLXArray,
        gate: MLXArray,
        compressRate: Int
    ) -> (MLXArray, MLXArray, Int) {
        let firstWindowPosition = (entryCount[name] ?? 0) * compressRate
        var kv = kv
        var gate = gate
        if let bufferedKV = bufferKV[name], let bufferedGate = bufferGate[name], bufferedKV.dim(1) > 0 {
            kv = concatenated([bufferedKV, kv], axis: 1)
            gate = concatenated([bufferedGate, gate], axis: 1)
        }

        let usable = (kv.dim(1) / compressRate) * compressRate
        if usable < kv.dim(1) {
            bufferKV[name] = kv[0..., usable..., 0...]
            bufferGate[name] = gate[0..., usable..., 0...]
        } else {
            bufferKV.removeValue(forKey: name)
            bufferGate.removeValue(forKey: name)
        }

        return (kv[0..., ..<usable, 0...], gate[0..., ..<usable, 0...], firstWindowPosition)
    }

    func updateCompressedState(name: String, compressed: MLXArray) -> MLXArray {
        if let previous = compressedKV[name], compressed.dim(1) > 0 {
            compressedKV[name] = concatenated([previous, compressed], axis: 1)
        } else if compressedKV[name] == nil {
            compressedKV[name] = compressed
        }
        entryCount[name, default: 0] += compressed.dim(1)
        return compressedKV[name] ?? compressed
    }

    func updateOverlapState(
        name: String,
        chunkKV: MLXArray,
        chunkGate: MLXArray,
        headDim: Int
    ) -> (MLXArray?, MLXArray?) {
        let priorKV = overlapKV[name]
        let priorGate = overlapGate[name]
        guard chunkKV.dim(1) > 0 else { return (priorKV, priorGate) }
        let lastWindow = chunkKV.dim(1) - 1
        overlapKV[name] = chunkKV[0..., lastWindow, 0..., ..<headDim]
        overlapGate[name] = chunkGate[0..., lastWindow, 0..., ..<headDim]
        return (priorKV, priorGate)
    }

    var state: [MLXArray] {
        get { keys.map { [$0] } ?? [] }
        set {
            keys = newValue.first
            offset = keys?.dim(2) ?? 0
        }
    }

    var metaState: [String] {
        get { [layerType.rawValue, String(slidingWindow), String(offset)] }
        set {
            if newValue.count >= 3, let restoredOffset = Int(newValue[2]) {
                offset = restoredOffset
            }
        }
    }

    var isTrimmable: Bool { true }

    @discardableResult
    func trim(_ n: Int) -> Int {
        let trimmed = min(offset, n)
        offset -= trimmed
        return trimmed
    }

    func makeMask(
        n: Int,
        windowSize: Int?,
        returnArray: Bool
    ) -> MLXFast.ScaledDotProductAttentionMaskMode {
        guard n > 1 else { return .none }
        let cappedOffset = min(max(slidingWindow - 1, 0), offset)
        return .array(createCausalMask(n: n, offset: cappedOffset, windowSize: slidingWindow))
    }

    func innerState() -> [MLXArray] {
        keys.map { [$0] } ?? []
    }

    func copy() -> any KVCache {
        let copy = PinesDeepseekV4KVCache(layerType: layerType, slidingWindow: slidingWindow)
        copy.offset = offset
        copy.keys = keys
        copy.bufferKV = bufferKV
        copy.bufferGate = bufferGate
        copy.compressedKV = compressedKV
        copy.entryCount = entryCount
        copy.overlapKV = overlapKV
        copy.overlapGate = overlapGate
        return copy
    }

    var debugDescription: String {
        "PinesDeepseekV4KVCache(type: \(layerType.rawValue), offset: \(offset), keys: \(keys?.shape.description ?? "-"))"
    }
}

private final class PinesDeepseekV4RotaryEmbedding {
    private let ropeDim: Int
    private let mainInvFreq: MLXArray
    private let compressInvFreq: MLXArray

    init(_ config: PinesDeepseekV4Configuration) {
        self.ropeDim = config.qkRopeHeadDim
        self.mainInvFreq = Self.inverseFrequencies(
            dim: config.qkRopeHeadDim,
            base: config.ropeTheta,
            scaling: nil
        )
        self.compressInvFreq = Self.inverseFrequencies(
            dim: config.qkRopeHeadDim,
            base: config.compressRopeTheta,
            scaling: config.ropeScaling
        )
    }

    private static func inverseFrequencies(
        dim: Int,
        base: Float,
        scaling: [String: StringOrNumber]?
    ) -> MLXArray {
        let indices = MLXArray(stride(from: 0, to: dim, by: 2)).asType(.float32)
        guard let scaling else {
            return 1.0 / MLX.pow(MLXArray(base), indices / Float(dim))
        }
        let ropeType: String? = switch scaling["type"] ?? scaling["rope_type"] {
        case .string(let value):
            value
        default:
            nil
        }
        guard ropeType == "yarn" else {
            return 1.0 / MLX.pow(MLXArray(base), indices / Float(dim))
        }

        let factor = scaling["factor"]?.asFloat() ?? 1
        let originalMax = scaling["original_max_position_embeddings"]?.asFloat() ?? 4096
        let betaFast = scaling["beta_fast"]?.asFloat() ?? 32
        let betaSlow = scaling["beta_slow"]?.asFloat() ?? 1
        let freqExtra = MLX.pow(MLXArray(base), indices / Float(dim))
        let freqInter = factor * MLX.pow(MLXArray(base), indices / Float(dim))
        let low = floor((Float(dim) * log(originalMax / (betaFast * 2 * Float.pi))) / (2 * log(base)))
        let high = ceil((Float(dim) * log(originalMax / (betaSlow * 2 * Float.pi))) / (2 * log(base)))
        let adjustedHigh = low == high ? high + 0.001 : high
        let ramp = clip((MLXArray(0 ..< (dim / 2)).asType(.float32) - low) / (adjustedHigh - low), min: 0, max: 1)
        let freqMask = 1.0 - ramp
        let freqs = (freqInter * freqExtra) / (freqInter * freqMask + freqExtra * (1 - freqMask))
        return 1.0 / freqs
    }

    func apply(
        _ x: MLXArray,
        positionIds: MLXArray,
        layerType: PinesDeepseekV4Configuration.AttentionLayerType,
        inverse: Bool = false
    ) -> MLXArray {
        let invFreq = layerType == .sliding ? mainInvFreq : compressInvFreq
        let headDim = x.dim(-1)
        let nopeDim = headDim - ropeDim
        let nope = nopeDim > 0 ? x[.ellipsis, ..<nopeDim] : nil
        let rope = x[.ellipsis, nopeDim...]

        var theta = positionIds.asType(.float32)[.ellipsis, .newAxis] * invFreq
        if x.ndim == 4 {
            if x.dim(1) == positionIds.dim(1) {
                theta = theta[0..., 0..., .newAxis, 0...]
            } else {
                theta = theta[0..., .newAxis, 0..., 0...]
            }
        }
        let cosTheta = cos(theta).asType(x.dtype)
        let sinTheta = (inverse ? -sin(theta) : sin(theta)).asType(x.dtype)
        let even = rope[.ellipsis, .stride(by: 2)]
        let odd = rope[.ellipsis, .stride(from: 1, by: 2)]
        let rotatedEven = even * cosTheta - odd * sinTheta
        let rotatedOdd = even * sinTheta + odd * cosTheta
        let rotated = stacked([rotatedEven, rotatedOdd], axis: -1).reshaped(rope.shape)

        if let nope {
            return concatenated([nope, rotated], axis: -1)
        }
        return rotated
    }
}

private final class PinesDeepseekV4UnweightedRMSNorm: Module, UnaryLayer {
    private let eps: Float

    init(eps: Float) {
        self.eps = eps
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        x * rsqrt(mean(x.asType(.float32).square(), axis: -1, keepDims: true) + eps).asType(x.dtype)
    }
}

private class PinesDeepseekV4GroupedLinear: Module, Quantizable {
    let groups: Int

    @ParameterInfo(key: "weight") var weight: MLXArray

    init(inputPerGroup: Int, outputPerGroup: Int, groups: Int) {
        self.groups = groups
        let scale = sqrt(1.0 / Float(inputPerGroup))
        _weight.wrappedValue = MLXRandom.uniform(-scale ..< scale, [outputPerGroup * groups, inputPerGroup])
        super.init()
    }

    init(weight: MLXArray, groups: Int) {
        self.groups = groups
        _weight.wrappedValue = weight
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        groupedLinear(x, weight: weight, groups: groups)
    }

    func toQuantized(groupSize: Int, bits: Int, mode: QuantizationMode) -> Module {
        PinesDeepseekV4QuantizedGroupedLinear(self, groupSize: groupSize, bits: bits, mode: mode)
    }
}

private final class PinesDeepseekV4QuantizedGroupedLinear: PinesDeepseekV4GroupedLinear, Quantized {
    let groupSize: Int
    let bits: Int
    let mode: QuantizationMode

    @ParameterInfo(key: "scales") var scales: MLXArray
    @ParameterInfo(key: "biases") var biases: MLXArray?

    init(
        _ other: PinesDeepseekV4GroupedLinear,
        groupSize: Int,
        bits: Int,
        mode: QuantizationMode
    ) {
        self.groupSize = groupSize
        self.bits = bits
        self.mode = mode
        let quantized = MLX.quantized(other.weight, groupSize: groupSize, bits: bits, mode: mode)
        _scales.wrappedValue = quantized.scales
        _biases.wrappedValue = quantized.biases
        super.init(weight: quantized.wq, groups: other.groups)
        freeze()
    }

    override func callAsFunction(_ x: MLXArray) -> MLXArray {
        let dequantizedWeight = dequantized(
            weight,
            scales: scales,
            biases: biases,
            groupSize: groupSize,
            bits: bits,
            mode: mode,
            dtype: x.dtype
        )
        return groupedLinear(x, weight: dequantizedWeight, groups: groups)
    }
}

private func groupedLinear(_ x: MLXArray, weight: MLXArray, groups: Int) -> MLXArray {
    let inputShape = Array(x.shape.dropLast(2))
    let hiddenDim = x.dim(-1)
    let weightByGroup = weight.reshaped(groups, -1, hiddenDim).transposed(0, 2, 1)
    let xByGroup = x.reshaped(-1, groups, hiddenDim).transposed(1, 0, 2)
    let y = matmul(xByGroup, weightByGroup).transposed(1, 0, 2)
    return y.reshaped(inputShape + [groups, -1])
}

private final class PinesDeepseekV4HyperConnection: Module {
    private let hcMult: Int
    private let sinkhornIterations: Int
    private let eps: Float
    private let inputNorm: PinesDeepseekV4UnweightedRMSNorm

    @ParameterInfo(key: "fn") var fn: MLXArray
    @ParameterInfo(key: "base") var base: MLXArray
    @ParameterInfo(key: "scale") var scale: MLXArray

    init(_ config: PinesDeepseekV4Configuration) {
        self.hcMult = config.hcMult
        self.sinkhornIterations = config.hcSinkhornIterations
        self.eps = config.hcEps
        self.inputNorm = PinesDeepseekV4UnweightedRMSNorm(eps: config.rmsNormEps)
        let mix = (2 + config.hcMult) * config.hcMult
        _fn.wrappedValue = zeros([mix, config.hcMult * config.hiddenSize])
        _base.wrappedValue = zeros([mix])
        _scale.wrappedValue = ones([3])
        super.init()
    }

    func callAsFunction(_ hiddenStreams: MLXArray) -> (MLXArray, MLXArray, MLXArray) {
        let flat = inputNorm(hiddenStreams.reshaped(hiddenStreams.dim(0), hiddenStreams.dim(1), -1).asType(.float32))
        let mixes = matmul(flat, fn.asType(.float32).T)
        let parts = split(mixes, indices: [hcMult, 2 * hcMult], axis: -1)
        let baseParts = split(base.asType(.float32), indices: [hcMult, 2 * hcMult], axis: -1)

        let pre = sigmoid(parts[0] * scale[0].asType(.float32) + baseParts[0]) + eps
        let post = 2 * sigmoid(parts[1] * scale[1].asType(.float32) + baseParts[1])
        var comb = softmax(
            parts[2].reshaped(hiddenStreams.dim(0), hiddenStreams.dim(1), hcMult, hcMult)
                * scale[2].asType(.float32)
                + baseParts[2].reshaped(hcMult, hcMult),
            axis: -1,
            precise: true
        ) + eps
        comb = comb / (comb.sum(axis: -2, keepDims: true) + eps)
        if sinkhornIterations > 1 {
            for _ in 0 ..< (sinkhornIterations - 1) {
                comb = comb / (comb.sum(axis: -1, keepDims: true) + eps)
                comb = comb / (comb.sum(axis: -2, keepDims: true) + eps)
            }
        }

        let collapsed = (pre[.ellipsis, .newAxis] * hiddenStreams).sum(axis: 2).asType(hiddenStreams.dtype)
        return (post, comb, collapsed)
    }
}

private final class PinesDeepseekV4HyperHead: Module, UnaryLayer {
    private let hcMult: Int
    private let eps: Float
    private let inputNorm: PinesDeepseekV4UnweightedRMSNorm

    @ParameterInfo(key: "fn") var fn: MLXArray
    @ParameterInfo(key: "base") var base: MLXArray
    @ParameterInfo(key: "scale") var scale: MLXArray

    init(_ config: PinesDeepseekV4Configuration) {
        self.hcMult = config.hcMult
        self.eps = config.hcEps
        self.inputNorm = PinesDeepseekV4UnweightedRMSNorm(eps: config.rmsNormEps)
        _fn.wrappedValue = zeros([config.hcMult, config.hcMult * config.hiddenSize])
        _base.wrappedValue = zeros([config.hcMult])
        _scale.wrappedValue = ones([1])
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let flat = inputNorm(x.reshaped(x.dim(0), x.dim(1), -1).asType(.float32))
        let mixes = matmul(flat, fn.asType(.float32).T)
        let pre = sigmoid(mixes * scale[0].asType(.float32) + base.asType(.float32)) + eps
        return (pre[.ellipsis, .newAxis] * x).sum(axis: 2).asType(x.dtype)
    }
}

private final class PinesDeepseekV4Attention: Module {
    private let config: PinesDeepseekV4Configuration
    private let layerType: PinesDeepseekV4Configuration.AttentionLayerType
    private let scale: Float
    private let qNormNoWeight: PinesDeepseekV4UnweightedRMSNorm
    private let rotary: PinesDeepseekV4RotaryEmbedding

    @ModuleInfo(key: "wq_a") var qAProj: Linear
    @ModuleInfo(key: "q_norm") var qANorm: RMSNorm
    @ModuleInfo(key: "wq_b") var qBProj: Linear
    @ModuleInfo(key: "wkv") var kvProj: Linear
    @ModuleInfo(key: "kv_norm") var kvNorm: RMSNorm
    @ModuleInfo(key: "wo_a") var oAProj: PinesDeepseekV4GroupedLinear
    @ModuleInfo(key: "wo_b") var oBProj: Linear
    @ParameterInfo(key: "attn_sink") var attentionSink: MLXArray
    @ModuleInfo(key: "compressor") var compressor: PinesDeepseekV4AttentionCompressor?

    init(_ config: PinesDeepseekV4Configuration, layerIndex: Int, rotary: PinesDeepseekV4RotaryEmbedding) {
        self.config = config
        self.layerType = config.layerTypes[layerIndex]
        self.scale = pow(Float(config.headDim), -0.5)
        self.qNormNoWeight = PinesDeepseekV4UnweightedRMSNorm(eps: config.rmsNormEps)
        self.rotary = rotary
        _qAProj.wrappedValue = Linear(config.hiddenSize, config.qLoraRank, bias: false)
        _qANorm.wrappedValue = RMSNorm(dimensions: config.qLoraRank, eps: config.rmsNormEps)
        _qBProj.wrappedValue = Linear(
            config.qLoraRank,
            config.attentionHeads * config.headDim,
            bias: false
        )
        _kvProj.wrappedValue = Linear(config.hiddenSize, config.headDim, bias: false)
        _kvNorm.wrappedValue = RMSNorm(dimensions: config.headDim, eps: config.rmsNormEps)
        _oAProj.wrappedValue = PinesDeepseekV4GroupedLinear(
            inputPerGroup: config.attentionHeads * config.headDim / config.oGroups,
            outputPerGroup: config.oLoraRank,
            groups: config.oGroups
        )
        _oBProj.wrappedValue = Linear(config.oGroups * config.oLoraRank, config.hiddenSize, bias: false)
        _attentionSink.wrappedValue = zeros([config.attentionHeads])
        if layerType != .sliding {
            _compressor.wrappedValue = PinesDeepseekV4AttentionCompressor(config, layerType: layerType, rotary: rotary)
        }
        super.init()
    }

    func callAsFunction(
        _ hiddenStates: MLXArray,
        positionIds: MLXArray,
        attentionMask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache?
    ) -> MLXArray {
        let batch = hiddenStates.dim(0)
        let length = hiddenStates.dim(1)

        let qResidual = qANorm(qAProj(hiddenStates))
        var queries = qBProj(qResidual)
            .reshaped(batch, length, config.attentionHeads, config.headDim)
            .transposed(0, 2, 1, 3)
        queries = qNormNoWeight(queries)
        queries = rotary.apply(queries, positionIds: positionIds, layerType: layerType)

        var kv = kvNorm(kvProj(hiddenStates))
            .reshaped(batch, length, 1, config.headDim)
            .transposed(0, 2, 1, 3)
        kv = rotary.apply(kv, positionIds: positionIds, layerType: layerType)

        var kvForAttention: MLXArray
        let deepseekCache = cache as? PinesDeepseekV4KVCache
        if let deepseekCache {
            kvForAttention = deepseekCache.update(keys: kv, values: kv).0
        } else if let cache {
            kvForAttention = cache.update(keys: kv, values: kv).0
        } else {
            kvForAttention = kv
        }

        var blockBias: MLXArray?
        if let compressor {
            let compressed = compressor(
                hiddenStates,
                qResidual: qResidual,
                positionIds: positionIds,
                cache: deepseekCache
            )
            kvForAttention = concatenated([kvForAttention, compressed.kv], axis: 2)
            blockBias = compressed.bias
        }

        var maskArray = additiveMask(
            from: attentionMask,
            batch: batch,
            sequenceLength: length,
            keyLength: kvForAttention.dim(2),
            dtype: queries.dtype
        )
        if let blockBias {
            let localKeyLength = kvForAttention.dim(2) - blockBias.dim(-1)
            let localMask = maskArray ?? zeros([batch, 1, length, localKeyLength], dtype: queries.dtype)
            let block = blockBias.asType(queries.dtype)
            maskArray = concatenated([localMask, block], axis: -1)
        }

        var output = scaledDotProductAttentionWithSink(
            queries: queries,
            keys: kvForAttention,
            values: kvForAttention,
            mask: maskArray,
            sink: attentionSink,
            scale: scale
        )
        output = rotary.apply(output.transposed(0, 2, 1, 3), positionIds: positionIds, layerType: layerType, inverse: true)
            .transposed(0, 2, 1, 3)
        let grouped = output.transposed(0, 2, 1, 3)
            .reshaped(batch, length, config.oGroups, -1)
        return oBProj(oAProj(grouped).flattened(start: 2))
    }
}

private final class PinesDeepseekV4AttentionCompressor: Module {
    private let config: PinesDeepseekV4Configuration
    private let layerType: PinesDeepseekV4Configuration.AttentionLayerType
    private let compressRate: Int
    private let rotary: PinesDeepseekV4RotaryEmbedding

    @ModuleInfo(key: "wkv") var kvProj: Linear
    @ModuleInfo(key: "wgate") var gateProj: Linear
    @ParameterInfo(key: "ape") var positionBias: MLXArray
    @ModuleInfo(key: "norm") var kvNorm: RMSNorm
    @ModuleInfo(key: "indexer") var indexer: PinesDeepseekV4Indexer?

    init(
        _ config: PinesDeepseekV4Configuration,
        layerType: PinesDeepseekV4Configuration.AttentionLayerType,
        rotary: PinesDeepseekV4RotaryEmbedding
    ) {
        self.config = config
        self.layerType = layerType
        self.compressRate = layerType == .compressedSparse ? config.compressRateCSA : config.compressRateHCA
        self.rotary = rotary
        let projectionDim = layerType == .compressedSparse ? 2 * config.headDim : config.headDim
        _kvProj.wrappedValue = Linear(config.hiddenSize, projectionDim, bias: false)
        _gateProj.wrappedValue = Linear(config.hiddenSize, projectionDim, bias: false)
        _positionBias.wrappedValue = zeros([compressRate, projectionDim])
        _kvNorm.wrappedValue = RMSNorm(dimensions: config.headDim, eps: config.rmsNormEps)
        if layerType == .compressedSparse {
            _indexer.wrappedValue = PinesDeepseekV4Indexer(config, rotary: rotary)
        }
        super.init()
    }

    func callAsFunction(
        _ hiddenStates: MLXArray,
        qResidual: MLXArray,
        positionIds: MLXArray,
        cache: PinesDeepseekV4KVCache?
    ) -> (kv: MLXArray, bias: MLXArray?) {
        let batch = hiddenStates.dim(0)
        let sequenceLength = hiddenStates.dim(1)
        var kv = kvProj(hiddenStates)
        var gate = gateProj(hiddenStates)

        let firstWindowPosition: Int
        if let cache {
            (kv, gate, firstWindowPosition) = cache.storeCompressionWeights(
                name: "compressor",
                kv: kv,
                gate: gate,
                compressRate: compressRate
            )
        } else {
            let usable = (kv.dim(1) / compressRate) * compressRate
            kv = kv[0..., ..<usable, 0...]
            gate = gate[0..., ..<usable, 0...]
            firstWindowPosition = 0
        }

        var compressed: MLXArray
        if kv.dim(1) > 0 {
            let windows = kv.dim(1) / compressRate
            if layerType == .compressedSparse {
                (kv, gate) = compressedSparseWindows(
                    kv: kv,
                    gate: gate,
                    batch: batch,
                    windows: windows,
                    cache: cache,
                    name: "compressor"
                )
            } else {
                kv = kv.reshaped(batch, windows, compressRate, -1)
                gate = gate.reshaped(batch, windows, compressRate, -1) + positionBias.asType(gate.dtype)
            }
            compressed = kvNorm((kv * softmax(gate.asType(.float32), axis: 2, precise: true).asType(kv.dtype)).sum(axis: 2))
            let positions = compressionPositions(
                batch: batch,
                windows: windows,
                firstWindowPosition: firstWindowPosition,
                rate: compressRate
            )
            compressed = rotary.apply(
                compressed[0..., .newAxis, 0..., 0...],
                positionIds: positions,
                layerType: .compressedSparse
            )
            .squeezed(axis: 1)
        } else {
            compressed = zeros([batch, 0, config.headDim], dtype: hiddenStates.dtype)
        }

        if let cache {
            compressed = cache.updateCompressedState(name: "compressor", compressed: compressed)
        }
        let compressedKV = compressed[0..., .newAxis, 0..., 0...]
        guard compressedKV.dim(2) > 0 else {
            return (compressedKV, nil)
        }

        if layerType == .heavilyCompressed {
            if sequenceLength == 1 {
                return (compressedKV, nil)
            }
            let entryIndices = MLXArray(Int32(0) ..< Int32(compressedKV.dim(2)))
            let causalThreshold = (positionIds + 1).floorDivide(compressRate)
            let future = entryIndices.reshaped(1, 1, 1, -1) .>= causalThreshold[0..., .newAxis, 0..., .newAxis]
            let bias = MLX.where(
                future,
                MLXArray(-1.0e9).asType(hiddenStates.dtype),
                MLXArray(0.0).asType(hiddenStates.dtype)
            )
            return (compressedKV, bias)
        }

        guard let indexer else { return (compressedKV, nil) }
        let indices = indexer(
            hiddenStates,
            qResidual: qResidual,
            positionIds: positionIds,
            cache: cache
        )
        let compressedLength = compressedKV.dim(2)
        let entryIndices = MLXArray(Int32(0) ..< Int32(compressedLength)).reshaped(1, 1, 1, -1)
        let valid = indices .>= 0
        let safeIndices = MLX.where(valid, indices, MLXArray(Int32(compressedLength)))
        let hits = (safeIndices[0..., 0..., 0..., .newAxis] .== entryIndices).any(axis: -2)
        let bias = MLX.where(
            hits,
            MLXArray(0.0).asType(hiddenStates.dtype),
            MLXArray(-1.0e9).asType(hiddenStates.dtype)
        )[0..., .newAxis, 0..., 0...]
        return (compressedKV, bias)
    }

    private func compressedSparseWindows(
        kv: MLXArray,
        gate: MLXArray,
        batch: Int,
        windows: Int,
        cache: PinesDeepseekV4KVCache?,
        name: String
    ) -> (MLXArray, MLXArray) {
        let ratio = compressRate
        let headDim = config.headDim
        let chunkKV = kv.reshaped(batch, windows, ratio, -1)
        let chunkGate = gate.reshaped(batch, windows, ratio, -1) + positionBias.asType(gate.dtype)
        let newKV = zeros([batch, windows, 2 * ratio, headDim], dtype: kv.dtype)
        let newGate = full(
            [batch, windows, 2 * ratio, headDim],
            values: MLXArray(-1.0e9).asType(gate.dtype),
            dtype: gate.dtype
        )
        newKV[0..., 0..., ratio..., 0...] = chunkKV[0..., 0..., 0..., headDim...]
        newGate[0..., 0..., ratio..., 0...] = chunkGate[0..., 0..., 0..., headDim...]
        if windows > 1 {
            newKV[0..., 1..., ..<ratio, 0...] = chunkKV[0..., ..<(windows - 1), 0..., ..<headDim]
            newGate[0..., 1..., ..<ratio, 0...] = chunkGate[0..., ..<(windows - 1), 0..., ..<headDim]
        }
        if let cache {
            let prior = cache.updateOverlapState(name: name, chunkKV: chunkKV, chunkGate: chunkGate, headDim: headDim)
            if let priorKV = prior.0, let priorGate = prior.1 {
                newKV[0..., 0, ..<ratio, 0...] = priorKV.asType(newKV.dtype)
                newGate[0..., 0, ..<ratio, 0...] = priorGate.asType(newGate.dtype)
            }
        }
        return (newKV, newGate)
    }
}

private final class PinesDeepseekV4Indexer: Module {
    private let config: PinesDeepseekV4Configuration
    private let compressRate: Int
    private let scale: Float
    private let weightsScale: Float
    private let rotary: PinesDeepseekV4RotaryEmbedding

    @ModuleInfo(key: "compressor") var compressor: PinesDeepseekV4IndexerCompressor
    @ModuleInfo(key: "wq_b") var qBProj: Linear
    @ModuleInfo(key: "weights_proj") var weightsProj: Linear

    init(_ config: PinesDeepseekV4Configuration, rotary: PinesDeepseekV4RotaryEmbedding) {
        self.config = config
        self.compressRate = config.compressRateCSA
        self.scale = pow(Float(config.indexHeadDim), -0.5)
        self.weightsScale = pow(Float(config.indexHeads), -0.5)
        self.rotary = rotary
        _compressor.wrappedValue = PinesDeepseekV4IndexerCompressor(config, rotary: rotary)
        _qBProj.wrappedValue = Linear(
            config.qLoraRank,
            config.indexHeads * config.indexHeadDim,
            bias: false
        )
        _weightsProj.wrappedValue = Linear(config.hiddenSize, config.indexHeads, bias: false)
        super.init()
    }

    func callAsFunction(
        _ hiddenStates: MLXArray,
        qResidual: MLXArray,
        positionIds: MLXArray,
        cache: PinesDeepseekV4KVCache?
    ) -> MLXArray {
        let batch = hiddenStates.dim(0)
        let length = hiddenStates.dim(1)
        let compressedKV = compressor(hiddenStates, positionIds: positionIds, cache: cache)
        let compressedLength = compressedKV.dim(1)
        guard compressedLength > 0 else {
            return zeros([batch, length, 0], dtype: .int32)
        }

        var queries = qBProj(qResidual)
            .reshaped(batch, length, config.indexHeads, config.indexHeadDim)
            .transposed(0, 2, 1, 3)
        queries = rotary.apply(queries, positionIds: positionIds, layerType: .compressedSparse)
            .transposed(0, 2, 1, 3)

        var scores = matmul(
            queries.asType(.float32),
            compressedKV.asType(.float32).transposed(0, 2, 1)[0..., .newAxis, 0..., 0...]
        )
        scores = relu(scores) * scale
        let weights = weightsProj(hiddenStates).asType(.float32) * weightsScale
        var indexScores = (scores * weights[0..., 0..., 0..., .newAxis]).sum(axis: 2)

        let causalThreshold = (positionIds + 1).floorDivide(compressRate)
        let entryIndices = MLXArray(Int32(0) ..< Int32(compressedLength))
        let futureMask = entryIndices.reshaped(1, 1, -1) .>= causalThreshold[0..., 0..., .newAxis]
        indexScores = MLX.where(futureMask, MLXArray(-1.0e9).asType(indexScores.dtype), indexScores)

        let topK = min(config.indexTopK, compressedLength)
        let selected = argPartition(-indexScores, kth: max(topK - 1, 0), axis: -1)[0..., 0..., ..<topK]
        let invalid = selected .>= causalThreshold[0..., 0..., .newAxis]
        return MLX.where(invalid, MLXArray(Int32(-1)), selected)
    }
}

private final class PinesDeepseekV4IndexerCompressor: Module {
    private let config: PinesDeepseekV4Configuration
    private let rotary: PinesDeepseekV4RotaryEmbedding

    @ModuleInfo(key: "wkv") var kvProj: Linear
    @ModuleInfo(key: "wgate") var gateProj: Linear
    @ParameterInfo(key: "ape") var positionBias: MLXArray
    @ModuleInfo(key: "norm") var kvNorm: RMSNorm

    init(_ config: PinesDeepseekV4Configuration, rotary: PinesDeepseekV4RotaryEmbedding) {
        self.config = config
        self.rotary = rotary
        _kvProj.wrappedValue = Linear(config.hiddenSize, 2 * config.indexHeadDim, bias: false)
        _gateProj.wrappedValue = Linear(config.hiddenSize, 2 * config.indexHeadDim, bias: false)
        _positionBias.wrappedValue = zeros([config.compressRateCSA, 2 * config.indexHeadDim])
        _kvNorm.wrappedValue = RMSNorm(dimensions: config.indexHeadDim, eps: config.rmsNormEps)
        super.init()
    }

    func callAsFunction(
        _ hiddenStates: MLXArray,
        positionIds: MLXArray,
        cache: PinesDeepseekV4KVCache?
    ) -> MLXArray {
        let batch = hiddenStates.dim(0)
        let rate = config.compressRateCSA
        var kv = kvProj(hiddenStates)
        var gate = gateProj(hiddenStates)
        let firstWindowPosition: Int
        if let cache {
            (kv, gate, firstWindowPosition) = cache.storeCompressionWeights(
                name: "indexer",
                kv: kv,
                gate: gate,
                compressRate: rate
            )
        } else {
            let usable = (kv.dim(1) / rate) * rate
            kv = kv[0..., ..<usable, 0...]
            gate = gate[0..., ..<usable, 0...]
            firstWindowPosition = 0
        }

        var compressed: MLXArray
        if kv.dim(1) > 0 {
            let windows = kv.dim(1) / rate
            let headDim = config.indexHeadDim
            let chunkKV = kv.reshaped(batch, windows, rate, -1)
            let chunkGate = gate.reshaped(batch, windows, rate, -1) + positionBias.asType(gate.dtype)
            let newKV = zeros([batch, windows, 2 * rate, headDim], dtype: kv.dtype)
            let newGate = full(
                [batch, windows, 2 * rate, headDim],
                values: MLXArray(-1.0e9).asType(gate.dtype),
                dtype: gate.dtype
            )
            newKV[0..., 0..., rate..., 0...] = chunkKV[0..., 0..., 0..., headDim...]
            newGate[0..., 0..., rate..., 0...] = chunkGate[0..., 0..., 0..., headDim...]
            if windows > 1 {
                newKV[0..., 1..., ..<rate, 0...] = chunkKV[0..., ..<(windows - 1), 0..., ..<headDim]
                newGate[0..., 1..., ..<rate, 0...] = chunkGate[0..., ..<(windows - 1), 0..., ..<headDim]
            }
            if let cache {
                let prior = cache.updateOverlapState(name: "indexer", chunkKV: chunkKV, chunkGate: chunkGate, headDim: headDim)
                if let priorKV = prior.0, let priorGate = prior.1 {
                    newKV[0..., 0, ..<rate, 0...] = priorKV.asType(newKV.dtype)
                    newGate[0..., 0, ..<rate, 0...] = priorGate.asType(newGate.dtype)
                }
            }
            compressed = kvNorm((newKV * softmax(newGate.asType(DType.float32), axis: 2, precise: true).asType(newKV.dtype)).sum(axis: 2))
            let positions = compressionPositions(
                batch: batch,
                windows: windows,
                firstWindowPosition: firstWindowPosition,
                rate: rate
            )
            compressed = rotary.apply(
                compressed[0..., .newAxis, 0..., 0...],
                positionIds: positions,
                layerType: .compressedSparse
            )
            .squeezed(axis: 1)
        } else {
            compressed = zeros([batch, 0, config.indexHeadDim], dtype: hiddenStates.dtype)
        }

        if let cache {
            return cache.updateCompressedState(name: "indexer", compressed: compressed)
        }
        return compressed
    }
}

private final class PinesDeepseekV4MLP: Module, UnaryLayer {
    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear

    init(hiddenSize: Int, intermediateSize: Int) {
        _gateProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: false)
        _upProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: false)
        _downProj.wrappedValue = Linear(intermediateSize, hiddenSize, bias: false)
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        downProj(silu(gateProj(x)) * upProj(x))
    }
}

private final class PinesDeepseekV4Experts: Module {
    private let limit: Float

    @ModuleInfo(key: "gate_proj") var gateProj: SwitchLinear
    @ModuleInfo(key: "up_proj") var upProj: SwitchLinear
    @ModuleInfo(key: "down_proj") var downProj: SwitchLinear

    init(_ config: PinesDeepseekV4Configuration) {
        self.limit = config.swigluLimit
        _gateProj.wrappedValue = SwitchLinear(
            inputDims: config.hiddenSize,
            outputDims: config.intermediateSize,
            numExperts: config.routedExperts,
            bias: false
        )
        _upProj.wrappedValue = SwitchLinear(
            inputDims: config.hiddenSize,
            outputDims: config.intermediateSize,
            numExperts: config.routedExperts,
            bias: false
        )
        _downProj.wrappedValue = SwitchLinear(
            inputDims: config.intermediateSize,
            outputDims: config.hiddenSize,
            numExperts: config.routedExperts,
            bias: false
        )
        super.init()
    }

    func callAsFunction(_ x: MLXArray, indices: MLXArray) -> MLXArray {
        var x = MLX.expandedDimensions(x, axes: [-2, -3])
        let doSort = indices.size >= 64
        var routedIndices = indices
        var inverseOrder = MLXArray()
        if doSort {
            (x, routedIndices, inverseOrder) = gatherSort(x: x, indices: indices)
        }

        let up = clip(upProj(x, routedIndices, sortedIndices: doSort), min: -limit, max: limit)
        let gate = clip(gateProj(x, routedIndices, sortedIndices: doSort), max: limit)
        x = downProj(silu(gate) * up, routedIndices, sortedIndices: doSort)

        if doSort {
            x = scatterUnsort(x: x, invOrder: inverseOrder, shape: indices.shape)
        }
        return MLX.squeezed(x, axis: -2)
    }
}

private final class PinesDeepseekV4Router: Module {
    private let config: PinesDeepseekV4Configuration
    private let isHash: Bool

    @ParameterInfo(key: "weight") var weight: MLXArray
    @ParameterInfo(key: "e_score_correction_bias") var correctionBias: MLXArray
    @ParameterInfo(key: "tid2eid") var tokenToExpert: MLXArray

    init(_ config: PinesDeepseekV4Configuration, isHash: Bool) {
        self.config = config
        self.isHash = isHash
        _weight.wrappedValue = zeros([config.routedExperts, config.hiddenSize])
        _correctionBias.wrappedValue = zeros([config.routedExperts])
        _tokenToExpert.wrappedValue = zeros([config.vocabularySize, config.expertsPerToken], dtype: .int32)
        super.init()
    }

    func callAsFunction(_ hiddenStates: MLXArray, inputIds: MLXArray?) -> (MLXArray, MLXArray) {
        let flat = hiddenStates.reshaped(-1, config.hiddenSize)
        let logits = matmul(flat, weight.T)
        var scores: MLXArray
        switch config.scoringFunction {
        case "softmax":
            scores = softmax(logits, axis: -1, precise: true)
        case "sigmoid":
            scores = sigmoid(logits)
        default:
            scores = sqrt(softplus(logits))
        }

        let indices: MLXArray
        if isHash, let inputIds {
            indices = tokenToExpert[inputIds.reshaped(-1)].asType(.int32)
        } else {
            indices = argPartition(-(scores + correctionBias), kth: config.expertsPerToken - 1, axis: -1)[
                0..., ..<config.expertsPerToken
            ]
        }
        var weights = takeAlong(scores, indices, axis: -1)
        weights = weights / (weights.sum(axis: -1, keepDims: true) + 1e-20)
        return (indices, weights * config.routedScalingFactor)
    }
}

private final class PinesDeepseekV4SparseMoE: Module {
    private let config: PinesDeepseekV4Configuration
    private let isHash: Bool

    @ModuleInfo(key: "gate") var gate: PinesDeepseekV4Router
    @ModuleInfo(key: "switch_mlp") var experts: PinesDeepseekV4Experts
    @ModuleInfo(key: "shared_experts") var sharedExperts: PinesDeepseekV4MLP

    init(_ config: PinesDeepseekV4Configuration, layerIndex: Int) {
        self.config = config
        self.isHash = config.mlpLayerTypes[layerIndex] == .hashMoE
        _gate.wrappedValue = PinesDeepseekV4Router(config, isHash: isHash)
        _experts.wrappedValue = PinesDeepseekV4Experts(config)
        _sharedExperts.wrappedValue = PinesDeepseekV4MLP(
            hiddenSize: config.hiddenSize,
            intermediateSize: config.intermediateSize * max(config.sharedExperts, 1)
        )
        super.init()
    }

    func callAsFunction(_ hiddenStates: MLXArray, inputIds: MLXArray?) -> MLXArray {
        let (indices, scores) = gate(hiddenStates, inputIds: inputIds)
        var routed = experts(hiddenStates, indices: indices)
        routed = (routed * scores[.ellipsis, .newAxis]).sum(axis: -2)
        return routed + sharedExperts(hiddenStates)
    }
}

private final class PinesDeepseekV4DecoderLayer: Module {
    @ModuleInfo(key: "attn") var attention: PinesDeepseekV4Attention
    @ModuleInfo(key: "ffn") var ffn: PinesDeepseekV4SparseMoE
    @ModuleInfo(key: "attn_norm") var inputLayerNorm: RMSNorm
    @ModuleInfo(key: "ffn_norm") var postAttentionLayerNorm: RMSNorm
    @ModuleInfo(key: "attn_hc") var attentionHyperConnection: PinesDeepseekV4HyperConnection
    @ModuleInfo(key: "ffn_hc") var ffnHyperConnection: PinesDeepseekV4HyperConnection

    init(_ config: PinesDeepseekV4Configuration, layerIndex: Int, rotary: PinesDeepseekV4RotaryEmbedding) {
        _attention.wrappedValue = PinesDeepseekV4Attention(config, layerIndex: layerIndex, rotary: rotary)
        _ffn.wrappedValue = PinesDeepseekV4SparseMoE(config, layerIndex: layerIndex)
        _inputLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        _postAttentionLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        _attentionHyperConnection.wrappedValue = PinesDeepseekV4HyperConnection(config)
        _ffnHyperConnection.wrappedValue = PinesDeepseekV4HyperConnection(config)
        super.init()
    }

    func callAsFunction(
        _ hiddenStreams: MLXArray,
        inputIds: MLXArray,
        positionIds: MLXArray,
        attentionMask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache?
    ) -> MLXArray {
        let dtype = hiddenStreams.dtype
        var (post, comb, collapsed) = attentionHyperConnection(hiddenStreams)
        let attentionOutput = attention(
            inputLayerNorm(collapsed),
            positionIds: positionIds,
            attentionMask: attentionMask,
            cache: cache
        )
        var streams = post.asType(dtype)[.ellipsis, .newAxis] * attentionOutput[0..., 0..., .newAxis, 0...]
            + matmul(comb.asType(dtype).transposed(0, 1, 3, 2), hiddenStreams)

        (post, comb, collapsed) = ffnHyperConnection(streams)
        let mlpOutput = ffn(postAttentionLayerNorm(collapsed), inputIds: inputIds)
        streams = post.asType(dtype)[.ellipsis, .newAxis] * mlpOutput[0..., 0..., .newAxis, 0...]
            + matmul(comb.asType(dtype).transposed(0, 1, 3, 2), streams)
        return streams
    }
}

final class PinesDeepseekV4ModelInner: Module {
    private let config: PinesDeepseekV4Configuration
    private let rotary: PinesDeepseekV4RotaryEmbedding

    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo(key: "layers") fileprivate var layers: [PinesDeepseekV4DecoderLayer]
    @ModuleInfo(key: "norm") var norm: RMSNorm
    @ModuleInfo(key: "hc_head") fileprivate var hyperHead: PinesDeepseekV4HyperHead

    init(_ config: PinesDeepseekV4Configuration) {
        self.config = config
        let rotary = PinesDeepseekV4RotaryEmbedding(config)
        self.rotary = rotary
        _embedTokens.wrappedValue = Embedding(
            embeddingCount: config.vocabularySize,
            dimensions: config.hiddenSize
        )
        _layers.wrappedValue = (0 ..< config.hiddenLayers).map {
            PinesDeepseekV4DecoderLayer(config, layerIndex: $0, rotary: rotary)
        }
        _norm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        _hyperHead.wrappedValue = PinesDeepseekV4HyperHead(config)
        super.init()
    }

    func callAsFunction(_ inputIds: MLXArray, cache: [KVCache]?) -> MLXArray {
        let batch = inputIds.dim(0)
        let length = inputIds.dim(1)
        let offset = cache?.first?.offset ?? 0
        let basePositions = MLXArray(Int32(offset) ..< Int32(offset + length))
        let positionIds = tiled(basePositions[.newAxis, 0...], repetitions: [batch, 1])
        let embeddings = embedTokens(inputIds)
        var hiddenStreams = tiled(
            embeddings[0..., 0..., .newAxis, 0...],
            repetitions: [1, 1, config.hcMult, 1]
        )
        let attentionMask = createAttentionMask(h: embeddings, cache: cache?.first)
        for (index, layer) in layers.enumerated() {
            hiddenStreams = layer(
                hiddenStreams,
                inputIds: inputIds,
                positionIds: positionIds,
                attentionMask: attentionMask,
                cache: cache?[index]
            )
        }
        return norm(hyperHead(hiddenStreams))
    }
}

final class PinesDeepseekV4Model: Module, LLMModel {
    private let configuration: PinesDeepseekV4Configuration

    @ModuleInfo(key: "model") var model: PinesDeepseekV4ModelInner
    @ModuleInfo(key: "lm_head") var lmHead: Linear

    init(_ configuration: PinesDeepseekV4Configuration) {
        self.configuration = configuration
        _model.wrappedValue = PinesDeepseekV4ModelInner(configuration)
        _lmHead.wrappedValue = Linear(configuration.hiddenSize, configuration.vocabularySize, bias: false)
        super.init()
    }

    func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
        let hiddenStates = model(inputs, cache: cache)
        if configuration.tieWordEmbeddings {
            return model.embedTokens.asLinear(hiddenStates)
        }
        return lmHead(hiddenStates)
    }

    func newCache(parameters: GenerateParameters?) -> [KVCache] {
        configuration.layerTypes.map {
            PinesDeepseekV4KVCache(layerType: $0, slidingWindow: configuration.slidingWindow)
        }
    }

    var loraLayers: [Module] {
        model.layers
    }
}

private func scaledDotProductAttentionWithSink(
    queries: MLXArray,
    keys: MLXArray,
    values: MLXArray,
    mask: MLXArray?,
    sink: MLXArray,
    scale: Float
) -> MLXArray {
    let repeatedKeys = repeated(keys, count: queries.dim(1) / keys.dim(1), axis: 1)
    let repeatedValues = repeated(values, count: queries.dim(1) / values.dim(1), axis: 1)
    var weights = matmul(queries, repeatedKeys.transposed(0, 1, 3, 2)) * scale
    if let mask {
        weights = weights + mask.asType(weights.dtype)
    }
    let sinks = broadcast(
        sink.reshaped(1, -1, 1, 1).asType(weights.dtype),
        to: [queries.dim(0), queries.dim(1), queries.dim(2), 1]
    )
    var logits = concatenated([weights, sinks], axis: -1)
    logits = logits - logits.max(axis: -1, keepDims: true)
    let probabilities = softmax(logits, axis: -1, precise: true)
    let scores = probabilities[.ellipsis, ..<(probabilities.dim(-1) - 1)]
    return matmul(scores.asType(repeatedValues.dtype), repeatedValues)
}

private func additiveMask(
    from mask: MLXFast.ScaledDotProductAttentionMaskMode,
    batch: Int,
    sequenceLength: Int,
    keyLength: Int,
    dtype: DType
) -> MLXArray? {
    let rawMask: MLXArray?
    switch mask {
    case .none:
        rawMask = nil
    case .causal:
        rawMask = createCausalMask(n: sequenceLength, offset: max(keyLength - sequenceLength, 0))
    case .array(let maskArray):
        rawMask = maskArray
    case .arrays(let maskArrays):
        rawMask = maskArrays.first
    }
    guard var rawMask else { return nil }
    if rawMask.ndim == 2 {
        rawMask = rawMask[.newAxis, .newAxis, 0..., 0...]
    } else if rawMask.ndim == 3 {
        rawMask = rawMask[0..., .newAxis, 0..., 0...]
    }
    return MLX.where(
        rawMask,
        MLXArray(0.0).asType(dtype),
        MLXArray(-1.0e9).asType(dtype)
    )
}

private func compressionPositions(
    batch: Int,
    windows: Int,
    firstWindowPosition: Int,
    rate: Int
) -> MLXArray {
    let positions = MLXArray(Int32(0) ..< Int32(windows)) * Int32(rate) + Int32(firstWindowPosition)
    return tiled(positions[.newAxis, 0...], repetitions: [batch, 1])
}
#endif
