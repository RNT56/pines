#!/usr/bin/env bash
set -euo pipefail

tool="${1:?usage: install-ci-tool.sh <actionlint|gitleaks|shellcheck>}"
root="$(git rev-parse --show-toplevel)"
tool_root="${PINES_CI_TOOL_ROOT:-$root/build/tools/ci}"
bin_dir="$tool_root/bin"
mkdir -p "$bin_dir"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
machine="$(uname -m)"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

download_and_verify() {
  local url="$1"
  local expected_sha="$2"
  local archive="$3"
  local actual_sha

  curl -fsSL "$url" -o "$archive"
  actual_sha="$(sha256_file "$archive")"
  if [ "$actual_sha" != "$expected_sha" ]; then
    echo "Checksum mismatch for $url" >&2
    echo "expected: $expected_sha" >&2
    echo "actual:   $actual_sha" >&2
    exit 1
  fi
}

platform_key() {
  case "$os/$machine" in
    linux/x86_64|linux/amd64)
      echo linux-amd64
      ;;
    linux/arm64|linux/aarch64)
      echo linux-arm64
      ;;
    darwin/x86_64|darwin/amd64)
      echo darwin-amd64
      ;;
    darwin/arm64|darwin/aarch64)
      echo darwin-arm64
      ;;
    *)
      echo "Unsupported platform for pinned CI tool install: $os/$machine" >&2
      exit 1
      ;;
  esac
}

install_actionlint() {
  local version="1.7.12"
  local key archive_name expected_sha
  key="$(platform_key)"

  case "$key" in
    linux-amd64)
      archive_name="actionlint_${version}_linux_amd64.tar.gz"
      expected_sha="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
      ;;
    linux-arm64)
      archive_name="actionlint_${version}_linux_arm64.tar.gz"
      expected_sha="325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6"
      ;;
    darwin-amd64)
      archive_name="actionlint_${version}_darwin_amd64.tar.gz"
      expected_sha="5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644"
      ;;
    darwin-arm64)
      archive_name="actionlint_${version}_darwin_arm64.tar.gz"
      expected_sha="aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f"
      ;;
  esac

  install_from_tar_gz \
    "https://github.com/rhysd/actionlint/releases/download/v${version}/${archive_name}" \
    "$expected_sha" \
    actionlint \
    "actionlint-$version"
}

install_gitleaks() {
  local version="8.30.1"
  local key archive_name expected_sha
  key="$(platform_key)"

  case "$key" in
    linux-amd64)
      archive_name="gitleaks_${version}_linux_x64.tar.gz"
      expected_sha="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
      ;;
    linux-arm64)
      archive_name="gitleaks_${version}_linux_arm64.tar.gz"
      expected_sha="e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080"
      ;;
    darwin-amd64)
      archive_name="gitleaks_${version}_darwin_x64.tar.gz"
      expected_sha="dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709"
      ;;
    darwin-arm64)
      archive_name="gitleaks_${version}_darwin_arm64.tar.gz"
      expected_sha="b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5"
      ;;
  esac

  install_from_tar_gz \
    "https://github.com/gitleaks/gitleaks/releases/download/v${version}/${archive_name}" \
    "$expected_sha" \
    gitleaks \
    "gitleaks-$version"
}

install_shellcheck() {
  local version="0.11.0"
  local key archive_name expected_sha extract_dir
  key="$(platform_key)"

  case "$key" in
    linux-amd64)
      archive_name="shellcheck-v${version}.linux.x86_64.tar.xz"
      expected_sha="8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198"
      extract_dir="shellcheck-v${version}"
      ;;
    linux-arm64)
      archive_name="shellcheck-v${version}.linux.aarch64.tar.xz"
      expected_sha="12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588"
      extract_dir="shellcheck-v${version}"
      ;;
    darwin-amd64)
      archive_name="shellcheck-v${version}.darwin.x86_64.tar.xz"
      expected_sha="3c89db4edcab7cf1c27bff178882e0f6f27f7afdf54e859fa041fca10febe4c6"
      extract_dir="shellcheck-v${version}"
      ;;
    darwin-arm64)
      archive_name="shellcheck-v${version}.darwin.aarch64.tar.xz"
      expected_sha="56affdd8de5527894dca6dc3d7e0a99a873b0f004d7aabc30ae407d3f48b0a79"
      extract_dir="shellcheck-v${version}"
      ;;
  esac

  install_from_tar_xz \
    "https://github.com/koalaman/shellcheck/releases/download/v${version}/${archive_name}" \
    "$expected_sha" \
    "$extract_dir/shellcheck" \
    shellcheck \
    "shellcheck-$version"
}

install_from_tar_gz() {
  local url="$1"
  local expected_sha="$2"
  local binary_path="$3"
  local cache_name="$4"
  local install_path="$bin_dir/$binary_path"

  if [ -x "$install_path" ]; then
    echo "$install_path"
    return
  fi

  install_from_archive "$url" "$expected_sha" "$binary_path" "$binary_path" "$cache_name" z
}

install_from_tar_xz() {
  local url="$1"
  local expected_sha="$2"
  local archive_binary_path="$3"
  local binary_name="$4"
  local cache_name="$5"
  local install_path="$bin_dir/$binary_name"

  if [ -x "$install_path" ]; then
    echo "$install_path"
    return
  fi

  install_from_archive "$url" "$expected_sha" "$archive_binary_path" "$binary_name" "$cache_name" J
}

install_from_archive() {
  local url="$1"
  local expected_sha="$2"
  local archive_binary_path="$3"
  local binary_name="$4"
  local cache_name="$5"
  local compression_flag="$6"
  local install_path="$bin_dir/$binary_name"
  local archive tmp_dir

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/pines-ci-tool.XXXXXX")"
  archive="$tmp_dir/tool-archive"

  download_and_verify "$url" "$expected_sha" "$archive"
  mkdir -p "$tool_root/$cache_name"
  tar "-x${compression_flag}f" "$archive" -C "$tool_root/$cache_name"
  cp "$tool_root/$cache_name/$archive_binary_path" "$install_path"
  chmod +x "$install_path"
  rm -rf "$tmp_dir"
  echo "$install_path"
}

case "$tool" in
  actionlint)
    install_actionlint
    ;;
  gitleaks)
    install_gitleaks
    ;;
  shellcheck)
    install_shellcheck
    ;;
  *)
    echo "Unsupported CI tool: $tool" >&2
    exit 2
    ;;
esac
