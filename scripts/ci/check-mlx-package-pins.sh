#!/usr/bin/env bash
set -euo pipefail

MLX_SWIFT_REPO="${MLX_SWIFT_REPO:-https://github.com/RNT56/mlx-swift}"
MLX_SWIFT_LM_REPO="${MLX_SWIFT_LM_REPO:-https://github.com/RNT56/mlx-swift-lm}"
MLX_SWIFT_MIN_REVISION="6820f3c6b85bdd73a288f5796ba78c4cd40efd91"
MLX_SWIFT_LM_MIN_REVISION="861a9bd0e581317ddfce7446d306cbbb7916a75f"
MLX_SWIFT_NESTED_MLX_REVISION="75b756717154890033209aaba4ffc89b113c5998"
MLX_SWIFT_NESTED_MLX_C_REVISION="2abc34daff6ded246054d9e15b98870b5cd08b97"
PROJECT_FILE="Pines.xcodeproj/project.pbxproj"

OLD_MLX_SWIFT_REVISIONS=(
  "8f0718404a323698c7b5730f2de3af2b5e21f854"
  "48375f1d8f0694dee2ce8aab7f46be50c5297aec"
  "5db40d34a96a9c6889b6583d6cc09f8b8f05ea5e"
  "a63a5b1b412c979b91e4e0347b35845d2bb236c0"
  "c22a4b50e041295c53c303a5b3f60791dcd9967f"
  "2577c8856ddfb05cad0da4eda7b502cbb5d99a3f"
  "221ef73921c1d2bb92fc545168120e57545bac22"
  "a90b1097df45e4e70b6e0bb367624f8f5857970b"
  "2b0bd735a0cf18e0bdb87d1b066e2e9127299e08"
)
OLD_MLX_SWIFT_LM_REVISIONS=(
  "915a08dc8315b825b7f86109f12ba4d62d34f186"
  "bf7bab132f9810d8ab3e5c6e0adbcf3db0b40551"
  "bb5f6f837896503b1f660eaeed2850fb0f232a64"
  "fbae29300f38e9988a010997828e2aa08a32c338"
  "e39787395c977549e1ba112ee2fd7eb509d57f30"
  "85fc3225237fb41cc24f5d97eab0a92f2fef1a44"
  "c5a41b3995b67ad399b6f5a3bef324054447dc21"
  "8861b2d9746128f3461b71deee5bf94ec3817a78"
  "ef066d0999150a8970025101e6f0d55cb44afca0"
  "51cd9cb986f941c352902bf121173b16947316ad"
  "2178543c34f6ff86989a485b60670f01f6c125a3"
  "c596b40cf3ac831f26006ee046dbabbb580b7c3b"
  "eafe506864b61434929e88d1b07d523b00703fd1"
  "0c3863ae7e6d6a7cb160e924eee0898c9b49e6ff"
  "50e5bd416da5d144616a5e1f91758fa05ac792a7"
  "3fe1bd17ee2dcd01f96d0b74fc8bac34740d4b92"
  "af28d8a0e28a5f7d8a012ed66a1470ac00c6f20c"
  "bc1a5383e3f0bd2127ac07cc14cd259021a9b826"
)

fail() {
  echo "$1" >&2
  exit 1
}

is_sha() {
  [[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

project_yml_revision() {
  local package="$1"
  awk -v package="$package" '
    $1 == package ":" { in_package = 1; next }
    in_package && $1 == "revision:" { print $2; exit }
    in_package && $0 ~ /^  [[:alnum:]_]+:/ { exit }
  ' project.yml
}

pbxproj_revision() {
  local repository="$1"
  awk -v repository="$repository" '
    index($0, "/* XCRemoteSwiftPackageReference \"" repository "\" */ = {") { in_package = 1; next }
    in_package && $1 == "revision" {
      value = $3
      gsub(/[;"]/, "", value)
      print value
      exit
    }
    in_package && $0 ~ /^\t\t};/ { exit }
  ' "$PROJECT_FILE"
}

require_sha() {
  local name="$1"
  local value="$2"

  if ! is_sha "$value"; then
    fail "$name revision is missing or is not a 40-character lowercase SHA: $value"
  fi
}

require_absent() {
  local file="$1"
  local revision="$2"
  local message="$3"

  if grep -q "$revision" "$file"; then
    fail "$message"
  fi
}

verify_not_below_minimum() {
  local name="$1"
  local repo="$2"
  local revision="$3"
  local minimum="$4"

  if [[ "$revision" == "$minimum" ]]; then
    return 0
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  git -C "$tmp_dir" init -q
  if ! git -C "$tmp_dir" fetch --quiet --filter=blob:none "$repo" "$minimum" "$revision"; then
    fail "Unable to fetch $name revisions from $repo for ancestry validation."
  fi
  if ! git -C "$tmp_dir" merge-base --is-ancestor "$minimum" "$revision"; then
    fail "$name revision $revision is below known-good minimum $minimum."
  fi
  rm -rf "$tmp_dir"
}

verify_nested_mlx_revisions() {
  local revision="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  git -C "$tmp_dir" init -q
  if ! git -C "$tmp_dir" fetch --quiet --depth=1 "$MLX_SWIFT_REPO" "$revision"; then
    fail "Unable to fetch mlx-swift revision $revision to inspect nested mlx pin."
  fi

  local nested_revision
  nested_revision="$(
    git -C "$tmp_dir" ls-tree FETCH_HEAD:Source/Cmlx mlx |
      awk '$2 == "commit" && $4 == "mlx" { print $3 }'
  )"
  if [[ "$nested_revision" != "$MLX_SWIFT_NESTED_MLX_REVISION" ]]; then
    fail "mlx-swift revision $revision embeds mlx $nested_revision, expected $MLX_SWIFT_NESTED_MLX_REVISION."
  fi

  local nested_mlx_c_revision
  nested_mlx_c_revision="$(
    git -C "$tmp_dir" ls-tree FETCH_HEAD:Source/Cmlx mlx-c |
      awk '$2 == "commit" && $4 == "mlx-c" { print $3 }'
  )"
  if [[ "$nested_mlx_c_revision" != "$MLX_SWIFT_NESTED_MLX_C_REVISION" ]]; then
    fail "mlx-swift revision $revision embeds mlx-c $nested_mlx_c_revision, expected $MLX_SWIFT_NESTED_MLX_C_REVISION."
  fi
  rm -rf "$tmp_dir"
}

echo "Checking MLX fork package pins..."

project_mlx_swift_revision="$(project_yml_revision MLXSwift)"
project_mlx_swift_lm_revision="$(project_yml_revision MLXSwiftLM)"
pbx_mlx_swift_revision="$(pbxproj_revision mlx-swift)"
pbx_mlx_swift_lm_revision="$(pbxproj_revision mlx-swift-lm)"

require_sha "project.yml mlx-swift" "$project_mlx_swift_revision"
require_sha "project.yml mlx-swift-lm" "$project_mlx_swift_lm_revision"
require_sha "Pines.xcodeproj mlx-swift" "$pbx_mlx_swift_revision"
require_sha "Pines.xcodeproj mlx-swift-lm" "$pbx_mlx_swift_lm_revision"

if [[ "$project_mlx_swift_revision" != "$pbx_mlx_swift_revision" ]]; then
  fail "project.yml and Pines.xcodeproj disagree for mlx-swift: $project_mlx_swift_revision vs $pbx_mlx_swift_revision."
fi
if [[ "$project_mlx_swift_lm_revision" != "$pbx_mlx_swift_lm_revision" ]]; then
  fail "project.yml and Pines.xcodeproj disagree for mlx-swift-lm: $project_mlx_swift_lm_revision vs $pbx_mlx_swift_lm_revision."
fi

for revision in "${OLD_MLX_SWIFT_REVISIONS[@]}"; do
  require_absent project.yml "$revision" "project.yml still references an obsolete mlx-swift revision."
  require_absent "$PROJECT_FILE" "$revision" "Generated Xcode project still references an obsolete mlx-swift revision."
done
for revision in "${OLD_MLX_SWIFT_LM_REVISIONS[@]}"; do
  require_absent project.yml "$revision" "project.yml still references an obsolete mlx-swift-lm revision."
  require_absent "$PROJECT_FILE" "$revision" "Generated Xcode project still references an obsolete mlx-swift-lm revision."
done

verify_not_below_minimum "mlx-swift" "$MLX_SWIFT_REPO" "$project_mlx_swift_revision" "$MLX_SWIFT_MIN_REVISION"
verify_not_below_minimum "mlx-swift-lm" "$MLX_SWIFT_LM_REPO" "$project_mlx_swift_lm_revision" "$MLX_SWIFT_LM_MIN_REVISION"
verify_nested_mlx_revisions "$project_mlx_swift_revision"

echo "MLX fork package pins are aligned and at or above the known-good minimum revisions."
