#!/usr/bin/env bash
set -euo pipefail

tag="${1:?usage: generate-release-sbom.sh <tag> <output>}"
output="${2:?usage: generate-release-sbom.sh <tag> <output>}"
root="$(git rev-parse --show-toplevel)"

cd "$root"

# Ruby source is intentionally single-quoted so Bash does not expand JSON strings.
# shellcheck disable=SC2016
ruby -rjson -rtime -e '
tag = ARGV.fetch(0)
output = ARGV.fetch(1)

components = {}

def add_component(components, component)
  key = [component["type"], component["name"], component["version"], component["bom-ref"]].join("\0")
  components[key] ||= component
end

def swift_purl(location, version, revision)
  return nil unless location&.match?(%r{\Ahttps://github\.com/([^/]+)/([^/.]+)(?:\.git)?\z})

  owner = Regexp.last_match(1)
  repo = Regexp.last_match(2)
  qualifier = version || revision
  qualifier ? "pkg:github/#{owner}/#{repo}@#{qualifier}" : "pkg:github/#{owner}/#{repo}"
end

def add_swift_lock(components, path, scope)
  return unless File.file?(path)

  lock = JSON.parse(File.read(path))
  Array(lock["pins"]).each do |pin|
    state = pin.fetch("state", {})
    version = state["version"] || state["revision"] || state["branch"] || "unresolved"
    revision = state["revision"]
    component = {
      "type" => "library",
      "name" => pin.fetch("identity"),
      "version" => version,
      "bom-ref" => "swift:#{scope}:#{pin.fetch("identity")}@#{version}",
      "properties" => [
        { "name" => "pines:manifest", "value" => path },
        { "name" => "pines:swiftpm-scope", "value" => scope },
      ],
    }
    component["purl"] = swift_purl(pin["location"], state["version"], revision)
    component["externalReferences"] = [
      { "type" => "vcs", "url" => pin["location"] },
    ].compact
    component["properties"] << { "name" => "pines:revision", "value" => revision } if revision
    add_component(components, component.compact)
  end
end

def npm_name_from_lock_key(key)
  key.sub(%r{\Anode_modules/}, "")
end

def add_npm_lock(components, path)
  return unless File.file?(path)

  lock = JSON.parse(File.read(path))
  lock.fetch("packages", {}).each do |key, package|
    next if key.empty?
    next unless key.start_with?("node_modules/")

    name = package["name"] || npm_name_from_lock_key(key)
    version = package["version"] || "unresolved"
    component = {
      "type" => "library",
      "name" => name,
      "version" => version,
      "bom-ref" => "npm:#{name}@#{version}",
      "properties" => [
        { "name" => "pines:manifest", "value" => path },
      ],
    }
    component["licenses"] = [{ "license" => { "name" => package["license"] } }] if package["license"]
    component["hashes"] = [{ "alg" => "SRI", "content" => package["integrity"] }] if package["integrity"]
    component["externalReferences"] = [{ "type" => "distribution", "url" => package["resolved"] }] if package["resolved"]
    add_component(components, component)
  end
end

add_swift_lock(components, "Package.resolved", "swift-package")
add_swift_lock(components, "Pines.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved", "xcode-app")
add_npm_lock(components, "site/package-lock.json")

metadata_component = {
  "type" => "application",
  "name" => "pines",
  "version" => tag.sub(/\Av/, ""),
  "bom-ref" => "application:pines@#{tag}",
}

bom = {
  "$schema" => "https://cyclonedx.org/schema/bom-1.6.schema.json",
  "bomFormat" => "CycloneDX",
  "specVersion" => "1.6",
  "version" => 1,
  "metadata" => {
    "timestamp" => (ENV["PINES_SBOM_TIMESTAMP"] || Time.now.utc.iso8601),
    "component" => metadata_component,
    "tools" => {
      "components" => [
        {
          "type" => "application",
          "name" => "scripts/ci/generate-release-sbom.sh",
          "version" => "1",
        },
      ],
    },
  },
  "components" => components.values.sort_by { |component| component.fetch("bom-ref") },
}

File.write(output, JSON.pretty_generate(bom) + "\n")
' "$tag" "$output"

echo "$output"
