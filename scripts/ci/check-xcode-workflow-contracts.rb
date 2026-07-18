# frozen_string_literal: true

required_environment = {
  "PINES_SIMULATOR_OPERATION_TIMEOUT_SECONDS" => "180",
  "PINES_XCODE_TEST_TIMEOUT_SECONDS" => "720",
  "PINES_XCODE_TEST_ATTEMPTS" => "1",
  "PINES_XCODE_UI_SHARD_ATTEMPTS" => "2",
  "PINES_XCODE_UI_TEST_MODE" => "smoke",
}

workflow_jobs = {
  ".github/workflows/ci.yml" => "xcode-project",
  ".github/workflows/release.yml" => "validate",
}

workflow_jobs.each do |path, job|
  workflow = File.read(path)
  match = workflow.match(/^  #{Regexp.escape(job)}:\n(?<body>.*?)(?=^  [A-Za-z0-9_-]+:\n|\z)/m)
  abort "#{path}: missing #{job} job" unless match

  body = match[:body]
  required_environment.each do |name, value|
    next if body.match?(/^      #{Regexp.escape(name)}:\s*#{Regexp.escape(value)}\s*$/)

    abort "#{path}: #{job} must set #{name}=#{value}"
  end
end
