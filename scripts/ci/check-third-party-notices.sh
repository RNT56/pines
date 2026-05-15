#!/usr/bin/env bash
set -euo pipefail

notices="THIRD_PARTY_NOTICES.md"

echo "Checking third-party notices inventory..."
test -f "$notices"

required_terms=(
  "MLXSwift"
  "MLXSwiftLM"
  "SwiftHuggingFace"
  "SwiftTransformers"
  "GRDB"
  "Swift Markdown"
  "Swift CMark"
  "HighlightSwift"
  "Highlight.js"
  "EventSource"
  "Swift Crypto"
  "AsyncHTTPClient"
  "SwiftNIO"
  "SwiftNIO Extras"
  "SwiftNIO HTTP/2"
  "SwiftNIO SSL"
  "SwiftNIO Transport Services"
  "Swift Log"
  "Swift Distributed Tracing"
  "Swift Service Context"
  "Swift Service Lifecycle"
  "Swift HTTP Types"
  "Swift HTTP Structured Headers"
  "Swift Certificates"
  "Swift ASN.1"
  "Swift Configuration"
  "Swift Algorithms"
  "Swift Async Algorithms"
  "Swift Atomics"
  "Swift System"
  "Swift Jinja"
  "Swift Collections"
  "Swift Numerics"
  "Swift Syntax"
  "Swift DocC Plugin"
  "Swift DocC SymbolKit"
  "yyjson"
  "swift-xet"
  "MIT License"
  "BSD-2-Clause License"
  "BSD-3-Clause License"
  "Apache-2.0 License Text"
  "SwiftCrypto Project"
)

for term in "${required_terms[@]}"; do
  if ! grep -q "$term" "$notices"; then
    echo "Missing third-party notice term: $term" >&2
    exit 1
  fi
done

echo "Third-party notices inventory passed."
