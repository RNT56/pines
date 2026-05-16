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

#endif
