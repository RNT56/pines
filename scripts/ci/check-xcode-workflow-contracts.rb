# frozen_string_literal: true

required_environment = {
  "PINES_SIMULATOR_OPERATION_TIMEOUT_SECONDS" => "180",
  "PINES_SIMULATOR_BOOT_TIMEOUT_SECONDS" => "600",
  "PINES_XCODE_TEST_TIMEOUT_SECONDS" => "720",
  "PINES_XCODE_TEST_ATTEMPTS" => "1",
  "PINES_XCODE_UI_SHARD_ATTEMPTS" => "2",
  "PINES_XCODE_UI_TEST_MODE" => "smoke",
}

workflow_jobs = {
  ".github/workflows/ci.yml" => { job: "xcode-project", timeout: "120" },
  ".github/workflows/release.yml" => { job: "validate", timeout: "150" },
}

workflow_jobs.each do |path, contract|
  job = contract.fetch(:job)
  workflow = File.read(path)
  match = workflow.match(/^  #{Regexp.escape(job)}:\n(?<body>.*?)(?=^  [A-Za-z0-9_-]+:\n|\z)/m)
  abort "#{path}: missing #{job} job" unless match

  body = match[:body]
  timeout = contract.fetch(:timeout)
  unless body.match?(/^    timeout-minutes:\s*#{Regexp.escape(timeout)}\s*$/)
    abort "#{path}: #{job} must set timeout-minutes=#{timeout}"
  end

  required_environment.each do |name, value|
    next if body.match?(/^      #{Regexp.escape(name)}:\s*#{Regexp.escape(value)}\s*$/)

    abort "#{path}: #{job} must set #{name}=#{value}"
  end
end

validation_script = File.read("scripts/ci/run-xcode-validation.sh")
bootstatus_timeout_calls = validation_script.scan(
  /run_with_timeout "\$boot_timeout_seconds" xcrun simctl bootstatus/,
).length
unless bootstatus_timeout_calls == 2
  abort "scripts/ci/run-xcode-validation.sh: both bootstatus calls must use the dedicated boot timeout"
end

artifact_smoke_shards = %w[
  testArtifactsLibraryAndDetail
  testArtifactsImageStudioConfiguration
  testArtifactsVideoConfiguration
  testArtifactsSpeechConfiguration
  testArtifactsResearchConfiguration
  testArtifactsResearchComposerFlow
  testArtifactsRunningResearch
]

artifact_smoke_shards.each do |test_name|
  expected = "PinesUITests/PinesUITests/#{test_name}"
  count = validation_script.scan(expected).length
  abort "scripts/ci/run-xcode-validation.sh: expected exactly one #{expected} smoke shard" unless count == 1
end

%w[
  testArtifactsLibraryAndImageStudio
  testArtifactsVideoAndSpeechConfiguration
  testArtifactsResearchComposerAndRunningWork
].each do |legacy_test_name|
  next unless validation_script.include?(legacy_test_name)

  abort "scripts/ci/run-xcode-validation.sh: combined Artifact smoke shard #{legacy_test_name} must stay split"
end
