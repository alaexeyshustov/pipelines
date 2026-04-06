---
paths:
  - "app/views/**/*.html.erb"
  - "app/views/**/*.turbo_stream.erb"
  - "app/helpers/**/*.rb"
---

# Views & Front-End Development Rules

Views are thin templates. Presentation logic lives in ViewComponents (see @view_components) and helpers; business workflows stay outside the view.

## Core Principles

1. **Logic-light Templates** – ERB templates should mostly contain structural HTML, iterations (`each`), and simple conditionals (`if`). Move branching, formatting, and reusable presentation logic into ViewComponents or helpers.
2. **Prepare data before render** – Prefer loading and shaping data before it reaches the view. Avoid inline queries or lazy-loading surprises that create N+1 problems.
3. **Hotwire First (Turbo)** – Prefer Turbo Frames and Turbo Streams for interactive HTML updates. Reach for custom JSON endpoints or bespoke JavaScript only when the interaction truly needs them.
4. **DOM as State (Stimulus)** – Prefer Stimulus for client-side interactivity. Keep state in the HTML (`data-*` attributes) when practical.
5. **Format in Helpers, Build in Components** – Use helpers for formatting values (dates, currency, strings) and components for composing markup.

## Logic and Queries

Prepare all data before it reaches the view. If a template needs to know whether a button should render, ask a domain-facing method or presenter-friendly predicate instead of calculating it inline.

```erb
<% if @user.subscriptions.where(status: 'active').exists? && @user.age > 18 %>
  <button>Upgrade</button>
<% end %>

<% if @user.eligible_for_upgrade? %>
  <button>Upgrade</button>
<% end %>
```

## Hotwire (Turbo Frames & Streams)

Use Turbo Frames to decompose pages into independent, lazily-loaded, or independently updatable contexts.

```erb
<div id="shopping_cart">
  <%= render "cart", cart: @cart %>
</div>

<%= turbo_frame_tag "shopping_cart" do %>
  <%= render "cart", cart: @cart %>
<% end %>
```

When a controller action needs to update multiple parts of the page simultaneously, prefer Turbo Streams over custom JavaScript.

```erb
<%= turbo_stream.append "comments", Comments::CommentComponent.new(comment: @comment) %>
<%= turbo_stream.replace "comment_count", partial: "count", locals: { count: @post.comments.size } %>
```

## Partials vs. View Components

We use both, but for strictly different purposes:

* **Use Partials (`_name.html.erb`)** for structural layout splitting (e.g., `_navbar.html.erb`, `_footer.html.erb`) or for very simple, logic-less HTML fragments that just need a local variable dumped into them.
* **Use View Components (`app/components/`)** for anything that requires Ruby logic, data transformation, conditional CSS classes, or yields structured slots (like Cards, Modals, Badges, Dropdowns).

```erb
<%= render "shared/button", color: "red", size: "large", icon: "trash", text: "Delete" %>

<%= render UI::ButtonComponent.new(variant: :danger, size: :lg, icon: :trash) do %>
  Delete
<% end %>
```

## Helpers

Rails Helpers (`app/helpers/`) should act as small formatting helpers. Prefer ViewComponents or partials for complex HTML structures.

```ruby
# WRONG - Building HTML in a helper. This is impossible to style or maintain.
module UsersHelper
  def user_avatar(user)
    content_tag(:div, class: "avatar-wrapper") do
      image_tag(user.avatar_url, class: "rounded-full") + 
      content_tag(:span, user.name, class: "font-bold")
    end
  end
end

# RIGHT - Helper for formatting data only
module UsersHelper
  def formatted_join_date(user)
    user.created_at.strftime("%B %d, %Y")
  end
end
# (Use a ViewComponent for the avatar HTML)
```

## Client-Side JavaScript (Stimulus)

Prefer Stimulus controllers over inline `<script>` tags or jQuery-style DOM manipulation.

```erb
<button onclick="document.getElementById('modal').style.display='none'">Close</button>

<div data-controller="modal">
  <button data-action="click->modal#close">Close</button>
</div>
```

## Quick Reference

| Do | Don't |
|----|-------|
| Use Turbo Frames for partial page updates | Reach for bespoke JS before standard Turbo flows |
| Attach Stimulus controllers for interaction | Scatter interaction logic across inline scripts |
| Extract logic to ViewComponents, helpers, or domain-facing predicates | Put `if/elsif/else` logic trees in ERB |
| Use helpers for dates, currency, strings | Use helpers to generate `<div>` trees |
| eager_load/includes before rendering | `.where` or `.find` inside the View |

## Common Mistakes

1. **The N+1 Query Trap** – Iterating over `@post.comments` when the relation was not preloaded.
2. **Over-engineering with JS** – Reaching for complex custom JavaScript when Turbo or a normal form submission would work.
3. **Bypassing Rails Conventions** – Hardcoding URLs instead of using route helpers.
4. **Fat Partials** – Partials with too many locals are often better expressed as a ViewComponent.
5. **Duplicating domain rules in ERB** – Ask a model/service-backed predicate instead of re-implementing logic in the template.

**Remember:** Views render prepared data. Components shape presentation. Business workflows stay outside the template.


