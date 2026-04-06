---
paths:
  - "sig/*.rbs"
  - "sig/**/*.rbs"
---

# RBS (Ruby Signatures) Development Rules

RBS files define the contracts of the application. They provide static typing, documentation, and editor autocomplete without compromising Ruby's dynamic runtime nature.
Signatures focus on the **public API** and **data boundaries** of the classes.

## Core Principles

1. **Avoid `untyped`** – Treat `untyped` as a last resort for genuinely hard-to-model dynamic behavior. Prefer Unions (`|`), Optionals (`?`), Generics (`[T]`), interfaces, or type aliases first.
2. **Type the Interface, Not the Object** – Embrace Ruby's duck typing. If a method accepts anything that can be `#call`ed or `#read`, define an `interface` rather than requiring a concrete class.
3. **Nil Safety is Paramount** – Always explicitly mark optional arguments or return values that can be `nil` using the `?` suffix (e.g., `String?`).
4. **Let Tooling Handle the Boilerplate** – We use `rbs_rails` (or similar tooling) to automatically generate signatures for ActiveRecord columns and standard Rails DSLs. Hand written RBS should focus on custom domain logic, POROs, and Services.
5. **Collection strictness** – Avoid bare `Array` or `Hash` in signatures. Type the elements whenever the shape is knowable: `Array[User]`, `Hash[Symbol, String]`.

## Clean Signatures

### 1. Concrete vs. Duck Typing

Don't force concrete classes when a method only cares about behavior.

```ruby.rbs
# WRONG - too restrictive, prevents passing mocks or decorators
class PaymentProcessor
  def charge: (CreditCard card) -> void
end

# RIGHT - accepts anything that acts like a chargeable token
interface _Chargeable
  def token: () -> String
  def amount: () -> Integer
end

class PaymentProcessor
  def charge: (_Chargeable card) -> void
end
```
### 2. Services and Standard Interfaces
Since our Services follow a strict .call pattern (as defined in the services guide), their signatures should be predictable.

```ruby.rbs
# sig/app/services/charge_card.rbs
class ChargeCard
  # Custom Result struct typing
  class Result
    attr_reader success: bool
    attr_reader error: String?
    attr_reader transaction: Stripe::Charge?
    def success?: () -> bool
  end

  # The class method delegates to the instance
  def self.call: (user: User) -> Result

  # Instance initialization and execution
  def initialize: (user: User) -> void
  def call: () -> Result

  private
  attr_reader user: User
end
```

### 3. Blocks and Callbacks

Be explicit about what blocks yield and what they are expected to return.

```ruby.rbs
# WRONG - ignores block arguments and returns
def map_users: () { () -> untyped } -> Array[untyped]

# RIGHT - explicit block signature
def map_users: [T] () { (User) -> T } -> Array[T]
```

## Organization and Naming

**Directory Mirroring:** The sig/ directory must exactly mirror the app/ and lib/ directories. (e.g., app/models/user.rb -> sig/app/models/user.rbs).
**Interfaces:** Prefix interface names with an underscore (_) by convention (e.g., _Reader, _Exportable).
**Namespaces:** Always open the full namespace block; do not use compact inline namespacing, as it can confuse the RBS parser.

```ruby.rbs
# WRONG
class Users::WelcomeEmail < ApplicationMailer
end

# RIGHT
module Users
  class WelcomeEmail < ApplicationMailer
    def welcome: (User user) -> void
  end
end
```

## Common Mistakes
1. **Reaching for `untyped` too early:** Exhaust more precise options first. If you must use `untyped`, keep it narrow and make sure the surrounding public API stays typed.
2. **Typing standard ActiveRecord attributes:** Don't manually type def email: () -> String inside a Model's RBS if it's a database column. The rbs_rails generator handles that. Only type custom methods.
3. **Using nil instead of void:** If a method is called for its side effects (like saving to a database or enqueuing a job) and the return value shouldn't be used, return void, not nil.
4. **Over-typing Private Methods:** Unless a private method contains highly complex domain logic where the compiler can catch bugs, focus your energy on the public API.
5. **Forgetting Keyword Argument Syntax:** In RBS, keyword arguments don't use the standard key: type hash syntax, they look like (key: Type). Example: def find: (id: Integer) -> User.

**Remember:** RBS is the contract between different parts of the system. Write signatures that tell the next developer exactly what they need to provide and exactly what they can rely on getting back.

## References

- [rbs](https://github.com/ruby/rbs) - Official CLI for working with RBS files (prototype, list, methods)
- [rbs_rails](https://github.com/pocke/rbs_rails) - Rails plugin for generating RBS files from ActiveRecord models and standard Rails DSLs
- [rbs_collection](https://github.com/ruby/gem_rbs_collection) – Collection of RBS files for popular gems
- [Steep](https://github.com/soutaro/steep) – Type checker that uses RBS

