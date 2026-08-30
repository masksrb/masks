# Run using bin/ci

CI.run do
  step "Style: Ruby", "bin/rubocop"
  step "Security: Rails defects", "bin/brakeman --no-pager"
  step "Security: Gem audit", "bin/bundler-audit"
  step "Tests", "bin/rails test"


  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
