
CI.run do
  step "Style: Ruby", "bin/rubocop"
  step "Security: Rails defects", "bin/brakeman --no-pager"
  step "Security: Gem audit", "bin/bundler-audit"
  step "Tests", "bin/rails test"
end
