---
name: view_components
description: Best practices for using ViewComponents in Rails applications, including component structure, rendering patterns, and testing strategies.
---

# ViewComponents Rails Skill

## Basic Usage

This skill is based on the [official ViewComponent guide](https://viewcomponent.org/guide/getting-started.html).
Components are subclasses of `ViewComponent::Base` and live in `app/components`. Name them for what they render, not what they accept (`AvatarComponent` not `UserComponent`).

```ruby
# app/components/example_component.rb
class ExampleComponent < ViewComponent::Base
  erb_template <<~ERB
    <span title="<%= @title %>"><%= content %></span>
  ERB

  def initialize(title:)
    @title = title
  end
end
```

Content passed as a block is captured and assigned to the `content` accessor:

```erb
<%# good – block content %>
<%= render(ExampleComponent.new(title: "my title")) do %>
  Hello, World!
<% end %>
```

String content can also be set with `#with_content` (no block needed):

```erb
<%# good – with_content %>
<%= render(ExampleComponent.new(title: "my title").with_content("Hello, World!")) %>
```

**Rendering to a string inside a controller** — use `render_in`, not `render` or `render_to_string`:

```ruby
# bad – triggers AbstractController::DoubleRenderError
@icon = render IconComponent.new("close")

# bad – renders the whole view as a string
@icon = render_to_string IconComponent.new("close")

# good
@icon = IconComponent.new("close").render_in(view_context)
```

**Rendering outside a view context** (background jobs, markdown processors, etc.):

```ruby
ApplicationController.new.view_context.render(MyComponent.new)
```

## Slots

Slots let a component accept multiple named blocks of content, including other components. Use `renders_one` for content rendered at most once, `renders_many` for collections.

### Passthrough slots

```ruby
# blog_component.rb
class BlogComponent < ViewComponent::Base
  renders_one :header
  renders_many :posts
end
```

```erb
<%# blog_component.html.erb %>
<h1><%= header %></h1>

<% posts.each do |post| %>
  <%= post %>
<% end %>
```

```erb
<%# index.html.erb %>
<%= render BlogComponent.new do |c| %>
  <% c.with_header { link_to "My blog", root_path } %>
  <% c.with_posts(blog.posts.map(&:title)) %>
<% end %>
```

### Predicate methods

Use `#{slot_name}?` to test whether a slot was provided:

```erb
<% if header? %>
  <h1><%= header %></h1>
<% end %>

<% if posts? %>
  <div class="posts">
    <% posts.each do |post| %><%= post %><% end %>
  </div>
<% else %>
  <p>No posts yet.</p>
<% end %>
```

### Component slots

Pass a component class (or nested class name as string) as the second argument:

```ruby
class BlogComponent < ViewComponent::Base
  renders_one :header, "HeaderComponent"   # nested – reference by string
  renders_many :posts, PostComponent       # external – reference by class

  class HeaderComponent < ViewComponent::Base
    def initialize(classes:) = @classes = classes
    def call = content_tag(:h1, content, class: @classes)
  end
end
```

```erb
<%= render BlogComponent.new do |c| %>
  <% c.with_header(classes: "text-xl") do %>
    <%= link_to "My Site", root_path %>
  <% end %>
  <% c.with_post(title: "First post") { "Really interesting stuff." } %>
<% end %>
```

### Lambda slots

Lambda slots are useful when a full component is overkill:

```ruby
class BlogComponent < ViewComponent::Base
  renders_one :header, ->(classes:, &block) do
    content_tag :h1, class: classes, &block
  end

  # wrap another component with preset defaults
  renders_many :posts, ->(title:, classes:) do
    PostComponent.new(title: title, classes: "base-class " + classes)
  end
end
```

Lambda slots can access parent state:

```ruby
class TableComponent < ViewComponent::Base
  renders_one :header, -> { HeaderComponent.new(selectable: @selectable) }

  def initialize(selectable: false) = @selectable = selectable
end
```

### Referencing slots in lifecycle hooks

Slot content is registered *after* `initialize`, so reference it in `before_render`:

```ruby
class BlogComponent < ViewComponent::Base
  renders_one :image
  renders_many :posts

  def before_render
    @post_classes = "PostContainer--hasImage" if image.present?
  end
end
```

### Polymorphic slots

```ruby
class ListItemComponent < ViewComponent::Base
  renders_one :visual, types: {
    icon: IconComponent,
    avatar: ->(size: 16, **args) { AvatarComponent.new(size: size, **args) }
  }
end
```

### Setting slot content without a block

```erb
<%# with_SLOT_NAME_content (no args needed) %>
<%= render(BlogComponent.new.with_header_content("My blog")) %>

<%# with_content (when args are needed) %>
<%= render BlogComponent.new do |c| %>
  <% c.with_header(classes: "title").with_content("My blog") %>
<% end %>
```

### Composability rule ⚠️

**Use `renders_many` when the collection size is known at render time.** Never loop-render children manually via `content` — the parent loses visibility and type-checking.

```ruby
# WRONG – parent can't see what's inside the block
render UI::SliderComponent.new do
  @slides.each { |s| render UI::SliderComponent::SlideComponent.new(name: s.name) }
end

# RIGHT – declare as a slot; pass the collection at render time
class UI::SliderComponent < ViewComponent::Base
  renders_many :slides, "SlideComponent"
  class SlideComponent < ViewComponent::Base
    def initialize(name:) = @name = name
  end
end

render UI::SliderComponent.new do |t|
  t.with_slides([{name: "Slide 1"}, {name: "Slide 2"}])
end
```

---

## Collections

Render a collection in a single call (like `render partial:`, but typed):

```erb
<%= render(ProductComponent.with_collection(@products)) %>
```

```ruby
class ProductComponent < ViewComponent::Base
  def initialize(product:)
    @product = product
  end
end
```

### Custom parameter name

```ruby
class ProductComponent < ViewComponent::Base
  with_collection_parameter :item

  def initialize(item:)
    @item = item
  end
end
```

### Additional arguments

```erb
<%= render(ProductComponent.with_collection(@products, notice: "hi")) %>
```

```ruby
class ProductComponent < ViewComponent::Base
  with_collection_parameter :item

  erb_template <<~ERB
    <li>
      <h2><%= @item.name %></h2>
      <span><%= @notice %></span>
    </li>
  ERB

  def initialize(item:, notice:)
    @item = item
    @notice = notice
  end
end
```

### Counter and iteration context

ViewComponent auto-defines `#{param}_counter` and `#{param}_iteration`:

```ruby
class ProductComponent < ViewComponent::Base
  def initialize(product:, product_counter:, product_iteration:)
    @product = product
    @counter = product_counter   # Integer index
    @iteration = product_iteration  # #index, #size, #first?, #last?
  end
end
```

### Spacer components

```erb
<%= render(ProductComponent.with_collection(@products, spacer_component: SpacerComponent.new)) %>
```

---

## Conditional Rendering

Implement `#render?` to encapsulate visibility logic inside the component instead of the caller:

```ruby
# bad – logic leaks into every caller
<% if current_user.requires_confirmation? %>
  <%= render(ConfirmEmailComponent.new(user: current_user)) %>
<% end %>

# good – component decides for itself
class ConfirmEmailComponent < ViewComponent::Base
  erb_template <<~ERB
    <div class="banner">Please confirm your email address.</div>
  ERB

  def initialize(user:) = @user = user

  def render?
    @user.requires_confirmation?
  end
end
```

```erb
<%# caller is always clean %>
<%= render(ConfirmEmailComponent.new(user: current_user)) %>
```

Use `assert_component_rendered` / `refute_component_rendered` from `ViewComponent::TestHelpers` to test this.

---

## Helpers

Helpers must be explicitly included:

```ruby
module IconHelper
  def icon(name) = tag.i(data: {feather: name.to_s})
end

class UserComponent < ViewComponent::Base
  include IconHelper

  def profile_icon = icon(:user)
end
```

Or use the `helpers` proxy (no include needed):

```ruby
class UserComponent < ViewComponent::Base
  delegate :icon, to: :helpers   # optional convenience

  def profile_icon = helpers.icon(:user)
end
```

### Nested URL helpers

Nested URL helpers can implicitly depend on the current request. Always pass options explicitly or use the proxy:

```ruby
# bad – implicit request dependency
edit_user_path

# good – explicit
edit_user_path(user: current_user)

# good – via proxy
helpers.edit_user_path
```

---

## Templates

### Inline template (preferred for simple components)

```ruby
class InlineErbComponent < ViewComponent::Base
  erb_template <<~ERB
    <h1>Hello, <%= @name %>!</h1>
  ERB

  def initialize(name) = @name = name
end
```

### Sibling file

Place the template next to the component file:

```
app/components/
├── example_component.rb
├── example_component.html.erb
```

### Sidecar subdirectory

```
app/components/
├── example_component.rb
└── example_component/
    └── example_component.html.erb
```

Generate with `--sidecar`: `bin/rails generate view_component:component Example title --sidecar`

### `#call` method (inline, no template file)

```ruby
class InlineComponent < ViewComponent::Base
  def call
    if active?
      link_to "Cancel", integration_path, method: :delete
    else
      link_to "Integrate now!", integration_path
    end
  end

  # Action Pack variant support
  def call_phone = link_to "Phone", phone_path
end
```

Note: `call_*` methods must be public.

### Template inheritance

Subclasses automatically inherit the parent's template:

```ruby
class MyLinkComponent < LinkComponent
  # falls back to LinkComponent's template if none defined
end
```

Render a parent template from a subclass:

```erb
<%# my_link_component.html.erb %>
<div class="wrapper">
  <%= render_parent %>
</div>
```

Use `render_parent_to_string` inside `#call`:

```ruby
def call
  content_tag("div") { render_parent_to_string }
end
```

### Trailing whitespace

```ruby
class MyComponent < ViewComponent::Base
  strip_trailing_whitespace        # strip
  strip_trailing_whitespace(false) # keep
end
```

---

## Lifecycle

### `#before_render`

Called after initialization, before rendering. Use when you need helpers or slot content:

```ruby
class ExampleComponent < ViewComponent::Base
  renders_one :image

  def before_render
    @my_icon = helpers.star_icon
    @extra_classes = "has-image" if image.present?
  end
end
```

### `#around_render`

Wraps the render call — useful for instrumentation:

```ruby
class ExampleComponent < ViewComponent::Base
  def around_render
    MyInstrumenter.instrument { yield }
  end
end
```

---

## Resources

[Getting started](https://viewcomponent.org/guide/getting-started.html) – Official getting-started guide.
[Slots](https://viewcomponent.org/guide/slots.html) – Full slots reference.
[Collections](https://viewcomponent.org/guide/collections.html) – Rendering collections.
[Conditional rendering](https://viewcomponent.org/guide/conditional_rendering.html) – `#render?` hook.
[Helpers](https://viewcomponent.org/guide/helpers.html) – Using Rails helpers inside components.
[Templates](https://viewcomponent.org/guide/templates.html) – Template options and inheritance.
[Lifecycle](https://viewcomponent.org/guide/lifecycle.html) – `before_render` / `around_render`.
[Best Practices](https://viewcomponent.org/best_practices.html) – Official best practices.
[Testing Guide](https://viewcomponent.org/guide/testing.html) – Testing ViewComponents.
