---
paths:
  - "app/components/*.rb"
  - "app/components/**/*.rb"
---

# View Components Development Rules

ViewComponents encapsulate UI rendering logic. They replace complex helper methods, partials with excessive locals, and repetitive markup. They act as pure functions: given the same inputs, they should always render the same output.

## Core Principles

1. **Ruby for Logic, ERB for Markup** – Templates must be "dumb". Any complex conditionals, iterations, or string formatting belongs in the Ruby class.
2. **No Database Queries** – Components must never execute ActiveRecord queries. They receive fully instantiated models or primitive data in their initializer. 
3. **No Global State** – Components should not rely on `session`, `request`, `params`, or `Current.user`. If a component needs the current user, it must be explicitly passed in.
4. **Composability via Slots** – Use slots (`renders_one`, `renders_many`) to yield structured content to the component instead of relying on complex configuration hashes or messy `content_tag` nesting.
5. **Sidecar Isolation** – Keep the `.rb` class, `.html.erb` template, and (if applicable) `.css`/`.js` files grouped together in the same directory.

## Clean Interfaces and Logic

Shift formatting and conditional logic out of the template to make the markup highly readable.

```ruby
# WRONG - Logic in the template
# app/components/status_badge_component.html.erb
<span class="<%= @status == 'active' ? 'bg-green text-white' : 'bg-gray text-black' %>">
  <%= @status.capitalize %>
</span>

# RIGHT - Logic in the Ruby class
# app/components/status_badge_component.rb
class StatusBadgeComponent < ViewComponent::Base
  def initialize(status:)
    @status = status.to_sym
  end

  def classes
    case @status
    when :active then "bg-green text-white"
    else "bg-gray text-black"
    end
  end

  def label
    @status.to_s.capitalize
  end
end

# app/components/status_badge_component.html.erb
<span class="<%= classes %>">
  <%= label %>
</span>
```

## Composability (Slots)

When building structural components (Cards, Modals, Layouts), do not force users to pass HTML strings or giant hashes into the initializer. Use Slots.

```ruby
# app/components/ui/card_component.rb
module UI
  class CardComponent < ViewComponent::Base
    renders_one :header
    renders_one :footer
    renders_many :actions, "ActionComponent"

    def initialize(title: nil)
      @title = title
    end

    class ActionComponent < ViewComponent::Base
      def initialize(label:, url:)
        @label = label
        @url = url
      end

      def call
        link_to @label, @url, class: "btn-sm"
      end
    end
  end
end
```

**Usage in a view:**
```erb
<%= render UI::CardComponent.new(title: "Account Settings") do |c| %>
  <% c.with_header do %>
    <h2 class="text-xl">Danger Zone</h2>
  <% end %>

  <p>Are you sure you want to delete your account?</p>

  <% c.with_action(label: "Cancel", url: back_path) %>
  <% c.with_action(label: "Delete", url: delete_account_path) %>
<% end %>
```

## Organization

Organize components functionally, not flatly. Use namespaces (e.g., `UI::` for generic design system elements, `Users::` for domain-specific elements).

```text
app/components/
├── ui/
│   ├── button_component.rb
│   ├── button_component.html.erb
│   ├── card_component.rb
│   └── card_component.html.erb
└── users/
    ├── profile_header_component.rb
    └── profile_header_component.html.erb
```

## Previews

**Every component must have a preview.** Previews serve as both interactive documentation and testing environments.

```ruby
# spec/components/previews/ui/card_component_preview.rb
module UI
  class CardComponentPreview < ViewComponent::Preview
    # @param title text
    def default(title: "Default Title")
      render(UI::CardComponent.new(title: title)) do |c|
        "This is the card body."
      end
    end

    def with_actions
      render(UI::CardComponent.new(title: "Actionable Card")) do |c|
        c.with_action(label: "Save", url: "#")
        "Card body goes here."
      end
    end
  end
end
```

## Quick Reference

| Do                                   | Don't                                    |
|--------------------------------------|------------------------------------------|
| Extract logic to `#methods` in `.rb` | Write `if/else` spaghetti in `.html.erb` |
| Use `renders_one` / `renders_many`   | Pass raw HTML strings into kwargs        |
| Pass `user` object to initializer    | Call `Current.user` inside the component |
| Group files in sidecar directories   | Scatter logic across global helpers      |
| Write Previews for every component   | Guess how components look in isolation   |
| Format display data in the component | Format display data in the Model         |

## Common Mistakes

1. **The N+1 Trap** – Running `user.posts.each` inside a component template when `posts` wasn't eager-loaded by the controller. Components cannot control eager loading; they just consume data.
2. **Replacing all partials blindly** – If a view snippet has no logic and is just 3 lines of static HTML, a standard Rails `partial` is fine. Use components when logic, state, or encapsulation is needed.
3. **Over-abstracting CSS** – Avoid creating a prop for every possible CSS class. Stick to design system variants (`variant: :primary`) instead of passthrough classes (`class: "mt-4 bg-red-500"`), unless providing a designated `html_options` hash for wrapper overrides.
4. **Depending on global helpers** – If you need a helper method, delegate to `helpers` explicitly (e.g., `helpers.number_to_currency`). Do not include global helper modules into the component class.

**Remember:** ViewComponents are pure functions for UI. Data goes in, isolated and predictable HTML comes out.
