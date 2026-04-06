---
paths:
  - "app/services/*.rb"
  - "app/services/**/*.rb"
---

# Services Development Rules

Services are the application's business-logic and orchestration layer. They coordinate complex business operations, external API calls, and processes that span multiple models.

## Core Principles

1. **Single Responsibility** – A service should own one workflow or use case. Name it with a strong verb that describes the action (e.g., `ProcessPayment`, `Users::SendWelcomeEmail`).
2. **Standardized Interface** – Every service exposes a single public method: `.call` or `#call`.
3. **Predictable Returns** – Services should return a predictable result (like a Struct, a Result object, or the primary active record object), not arbitrary booleans.
4. **No Framework Leaks** – Services should not know about HTTP requests, controllers, sessions, or `params`. Pass only the specific data or objects the service needs.
5. **Fail Loudly or Return Errors** – Use exceptions for unexpected failures (e.g., API downtime). For expected failures (e.g., invalid data), return an object that can be queried for success/failure and errors.

Use models for persistence and query primitives. Use services to coordinate those primitives into a business flow.

## The Standard Interface

We use the class-level `.call` convenience method which delegates to an instance. This keeps initialization and execution clean.

```ruby
# WRONG - multiple public methods, unclear entry point
class InvoiceGenerator
  def initialize(order)
    @order = order
  end

  def generate!
    # ...
  end

  def send_to_customer
    # ...
  end
end

# RIGHT - single entry point, verb-based naming
class SendInvoice
  def self.call(order:)
    new(order: order).call
  end

  def initialize(order:)
    @order = order
  end

  def call
    invoice = generate_invoice
    deliver(invoice)

    invoice
  end

  private

  attr_reader :order

  def generate_invoice
    # ...
  end

  def deliver(invoice)
    # ...
  end
end
```

## Handling Results and Control Flow
Do not use exceptions for the expected control flow (like a validation failing). Instead, return an object that the caller can interrogate.

```ruby
# WRONG - returning booleans and expecting caller to guess what went wrong
class ChargeCard
  def call
    return false if @user.no_payment_method?
    # ...
    true
  end
end

# RIGHT - returning a structured result
class ChargeCard
  Result = Data.define(:success, :error, :transaction) do
    def success? = success
  end

  def call
    return Result.new(success: false, error: "No payment method found", transaction: nil) if @user.no_payment_method?

    transaction = Stripe::Charge.create(...)
    Result.new(success: true, error: nil, transaction: transaction)
  rescue Stripe::CardError => e
    Result.new(success: false, error: e.message, transaction: nil)
  end
end
```

## Common Mistakes

1. **God workflows** – Naming a service `PaymentManager` and putting unrelated logic inside. Break it down into smaller services or collaborators with clear roles.
2. **Passing params directly** – Prefer passing fully instantiated models or well-shaped primitive arguments instead of `ActionController::Parameters`.
3. **Swallowing exceptions** – Catching StandardError and returning false. Let unexpected exceptions bubble up to your error tracker.
4. **Reaching into global state** – Relying on Current User or global variables. Always inject dependencies via initialization.
5. **Instantiating inside the controller without calling** – Always use the `Service.call(args)` or `Service.new.call` pattern to ensure execution happens predictably.

**Remember:** Services are your application's verb layer. If a business process requires multiple steps, crosses model boundaries, or touches external systems, put it in a cleanly named service.
