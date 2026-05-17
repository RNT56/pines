#!/usr/bin/env bash
set -euo pipefail

MLX_SWIFT_UPSTREAM_URL="${MLX_SWIFT_UPSTREAM_URL:-https://github.com/ml-explore/mlx-swift.git}"
MLX_SWIFT_LM_UPSTREAM_URL="${MLX_SWIFT_LM_UPSTREAM_URL:-https://github.com/ml-explore/mlx-swift-lm.git}"
MLX_SWIFT_FORK_URL="${MLX_SWIFT_FORK_URL:-https://github.com/RNT56/mlx-swift.git}"
MLX_SWIFT_LM_FORK_URL="${MLX_SWIFT_LM_FORK_URL:-https://github.com/RNT56/mlx-swift-lm.git}"

check_remote() {
  local name="$1"
  local url="$2"

  if [ -z "$url" ]; then
    echo "::warning::$name fork URL is not configured. Set ${name}_FORK_URL once the Schtack fork exists."
    return 0
  fi

  git ls-remote "$url" HEAD >/dev/null
}

git ls-remote "$MLX_SWIFT_UPSTREAM_URL" HEAD >/dev/null
git ls-remote "$MLX_SWIFT_LM_UPSTREAM_URL" HEAD >/dev/null
check_remote "MLX_SWIFT" "$MLX_SWIFT_FORK_URL"
check_remote "MLX_SWIFT_LM" "$MLX_SWIFT_LM_FORK_URL"

bash scripts/ci/check-mlx-package-pins.sh

if ! grep -q "TurboQuant" Sources/PinesCore/Inference/RuntimeTypes.swift; then
  echo "TurboQuant runtime types are missing." >&2
  exit 1
fi

if ! grep -q "TurboQuantRuntimeBackend" Sources/PinesCore/Inference/RuntimeTypes.swift; then
  echo "TurboQuant backend diagnostics are missing." >&2
  exit 1
fi

if ! grep -q "metalCodecAvailable" Sources/PinesCore/Inference/RuntimeTypes.swift; then
  echo "TurboQuant Metal codec diagnostics are missing." >&2
  exit 1
fi

if ! grep -q "metalAttentionAvailable" Sources/PinesCore/Inference/RuntimeTypes.swift; then
  echo "TurboQuant Metal attention diagnostics are missing." >&2
  exit 1
fi

if ! grep -q "activeAttentionPath" Sources/PinesCore/Inference/RuntimeTypes.swift; then
  echo "TurboQuant attention path diagnostics are missing." >&2
  exit 1
fi

if ! grep -q "vault_embeddings" Sources/PinesCore/Persistence/DatabaseSchema.swift; then
  echo "Vault embedding schema is missing." >&2
  exit 1
fi

echo "MLX upstream sync preflight passed."
