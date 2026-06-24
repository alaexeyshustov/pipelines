# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"
  step "Type coverage", "bin/rbs_audit coverage"
  step "RBS audit", "bin/rbs_audit audit --fail-on-gaps"



  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
