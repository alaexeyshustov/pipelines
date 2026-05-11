---
name: address_review
description: Address all open code review comments on the current branch's PR
---
1. Run `gh pr view --json number,reviews,comments` to get review comments
2. For each actionable comment, make the fix
3. Run `bundle exec rspec`, `rubocop`, `steep check`
4. Commit with message referencing the review, push
5. Reply to each addressed comment on the PR