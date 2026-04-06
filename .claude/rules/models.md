---
paths:
  - "app/models/*.rb"
  - "app/models/**/*.rb"
---

# Models Development Rules

Models own data mapping, persistence, validations, associations, scopes, queries, and state representation.
Services own business workflows and orchestration. Models expose intention-revealing interfaces so callers do not reach into associations or persistence details.

## Core Principles

1. **Message passing** – Ask objects, don't reach into their associations
2. **Pass objects, not IDs** – Within synchronous domain code, prefer method signatures that accept domain objects. At async/serialization boundaries (jobs, external APIs), pass IDs instead — see @jobs.
3. **Prefer ActiveRecord/Arel** – Reach for ActiveRecord query methods first. Use raw SQL only when database-specific capabilities or performance requirements justify it.
4. **Expose intent, not structure** – Add domain-facing predicates and commands so callers ask the model what they need without navigating internals.
5. **State representation belongs here** – Use simple state columns/enums for simple states and a state machine for complex workflows.
6. **Use concerns for shared behavior** - Namespaced concerns: `Card::Closeable` in `card/closeable.rb`

## Clean Interfaces

```ruby
# WRONG - leaking implementation
book.posts.where(user: user).exists?
book.posts.create!(user: user)

# RIGHT - clean interface
book.posts_from?(user)
book.add_post_from(user)

# Model exposes intent-based methods
class Book < ApplicationRecord
  def posts_from?(user)
    user_posts.exists?(user: user)
  end

  def add_post_from(user)
    user_posts.find_or_create_by(user: user)
  end
end
```

## State Management 

1. For simple, sequential states: Use Rails enum.
    ```ruby
    class Post < ApplicationRecord
      enum :status, { draft: 0, published: 1, archived: 2 }, default: :draft
    end
    ```
2. For complex or timestamped states use @state_machines

## Guidelines

- **Validations** – Use built-in validators, validate at the model level
- **Associations** - Use `:dependent`, `:inverse_of`, counter-caches
- **Scopes** – Named scopes for reusable queries
- **Callbacks** – Use sparingly; keep external side effects and multistep workflows in services
- **Queries** – Prefer ActiveRecord/Arel and avoid N+1 with `includes`

## Common Mistakes

1. **Leaking implementation** – Provide clean interface methods instead of exposing association traversal.
2. **Business workflows in callbacks** – Prefer explicit service entry points for multi-step operations and external effects.
3. **N+1 queries** – Use counter_cache, includes, and eager loading.
4. **View logic in models** – Keep display formatting in views, helpers, or ViewComponents.

**Remember:** Models define the persistence-facing interface and state. Services coordinate business workflows on top of them.
