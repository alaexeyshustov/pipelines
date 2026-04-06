---
paths:
  - "app/models/*.rb"
  - "app/models/**/*.rb"
---

# State Machines Style Guide

This rule applies to the same paths as @models and provides focused guidance for state management inside model files.

Use enums for simple state machines. Do not build custom state logic or use multiple boolean columns (is_published, is_archived).
For complex workflows use the AASM gem for state management. 

1. Always specify the database column explicitly (column: :state).
2. Use guard clauses for domain-level checks before allowing a transition.
3. Do NOT use any AASM callbacks (`before_transition`, `after_transition`, `after_commit`, etc.) for external side effects (like sending emails or charging credit cards). External side effects must be handled by the Service object that triggered the state change, or via background jobs. AASM callbacks are strictly for internal data normalization or touching related records.

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  include AASM
  # If the AASM block exceeds ~30 lines, extract it to a concern:
  # include Article::Stateful

  aasm column: :state do
    state :draft, initial: true
    state :in_review
    state :published
    state :archived

    event :submit do
      # Guard ensures domain requirements are met before transitioning
      transitions from: :draft, to: :in_review, guard: :content_ready?
    end

    event :publish do
      transitions from: :in_review, to: :published
    end

    event :archive do
      transitions from: [:draft, :in_review, :published], to: :archived
    end
  end

  private

  def content_ready?
    title.present? && body.length > 100
  end
end
```

## References

- [AASM](https://github.com/aasm/aasm)