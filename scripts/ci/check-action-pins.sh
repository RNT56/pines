#!/usr/bin/env bash
set -euo pipefail

ruby <<'RUBY'
failed = false

Dir[".github/workflows/*.{yml,yaml}"].sort.each do |path|
  File.readlines(path).each_with_index do |line, index|
    next unless line =~ /^\s*uses:\s*["']?([^"'\s#]+)["']?/

    action = Regexp.last_match(1)
    next if action.start_with?("./")
    next if action.start_with?("docker://")

    unless action.match?(/@[0-9a-f]{40}\z/)
      warn "#{path}:#{index + 1}: action reference is not pinned to a full commit SHA: #{action}"
      failed = true
    end
  end
end

exit(failed ? 1 : 0)
RUBY
