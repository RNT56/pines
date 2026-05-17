#!/usr/bin/env bash
set -euo pipefail

MLX_SWIFT_REPO="${MLX_SWIFT_REPO:-https://github.com/RNT56/mlx-swift}"
MLX_SWIFT_LM_REPO="${MLX_SWIFT_LM_REPO:-https://github.com/RNT56/mlx-swift-lm}"
MLX_SWIFT_MIN_REVISION="221ef73921c1d2bb92fc545168120e57545bac22"
MLX_SWIFT_LM_MIN_REVISION="ef066d0999150a8970025101e6f0d55cb44afca0"
MLX_SWIFT_NESTED_MLX_REVISION="d999c27ecd549e65f8f689bdd5c83648da977b81"
PROJECT_FILE="Pines.xcodeproj/project.pbxproj"

OLD_MLX_SWIFT_REVISIONS=(
  "a63a5b1b412c979b91e4e0347b35845d2bb236c0"
  "c22a4b50e041295c53c303a5b3f60791dcd9967f"
  "2577c8856ddfb05cad0da4eda7b502cbb5d99a3f"
)
OLD_MLX_SWIFT_LM_REVISIONS=(
  "85fc3225237fb41cc24f5d97eab0a92f2fef1a44"
  "c5a41b3995b67ad399b6f5a3bef324054447dc21"
  "8861b2d9746128f3461b71deee5bf94ec3817a78"
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

verify_nested_mlx_revision() {
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
verify_nested_mlx_revision "$project_mlx_swift_revision"

echo "MLX fork package pins are aligned and at or above the known-good minimum revisions."
