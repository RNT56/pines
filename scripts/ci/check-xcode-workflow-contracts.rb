# frozen_string_literal: true

required_environment = {
  "PINES_SIMULATOR_OPERATION_TIMEOUT_SECONDS" => "180",
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
