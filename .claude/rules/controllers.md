---
paths:
  - "app/controllers/*.rb"
  - "app/controllers/**/*.rb"
---

# Controllers Development Rules

Controllers are thin request handlers. They coordinate request/response, delegate persistence-facing behavior to models, and hand business workflows to services.

## Core Principles

1. **Thin controllers** – Keep actions focused on loading input, choosing collaborators, and returning a response. Delegate persistence/query concerns to models and business workflows to services.
2. **Hotwire/Turbo first** – Prefer Turbo-driven HTML flows for interactive UI. Add JSON/API responses only when an endpoint is intentionally API-shaped.
3. **Prefer RESTful actions** – Custom member/collection actions are allowed for orchestration workflows that don't fit a standard CRUD shape.

## Message Passing

Ask objects; don't reach into their associations. Delegate complex business logic to service objects.

```ruby
# WRONG - reaching into associations
@posts = book.posts.find_by(author: current_user)
@result = book.payments.where(status: :pending).process_for(current_user)

# RIGHT - ask the object
@posts = book.posts_for(current_user)
@result = PaymentService.call(book: book, user: current_user)
```

See @models for model-side interface patterns, @services for service objects, and @form_objects for form object patterns.


## Resourceful Routes

```ruby
resources :books do
  resource :posts, only: %i[create destroy] do
    post :publish, on: :member
  end
end
```

## Common Mistakes

1. **Checking state in views** – Move to a model method or another domain-facing predicate.
2. **Business workflows in controllers** – Move multi-step operations to a service object.
3. **Adding extra response formats without a clear need** – Default to the app's HTML/Turbo flow.
4. **Catching exceptions for control flow** – Prefer explicit branching and let unexpected exceptions propagate.
5. **Fat actions** – Extract collaboration into services or model methods.

**Remember:** Controllers coordinate. Models expose persistence/query interfaces; services implement business workflows.
