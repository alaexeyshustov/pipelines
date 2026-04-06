---
paths:
  - "app/jobs/*.rb"
  - "app/jobs/**/*.rb"
---

# Jobs Development Rules

Jobs are thin async dispatchers. They load the minimum context needed and hand the real work to a service or agent.

## Core Principles

1. **Idempotent** – Jobs MUST be safe to run multiple times.
2. **Prefer Thin Jobs** – Jobs orchestrate, they don't implement. If a job does more than load context and delegate, move that logic to a service or agent.
3. **Prefer visible failures** – Let errors raise by default. Use `discard_on` only for intentionally unrecoverable cases you fully understand.
4. **Use State machines** – For complex workflows, use a state machine (see @state_machines) to manage transitions and side effects.

## Idempotency

```ruby
# WRONG - doubles credits on retry
def perform(user_id)
  user = User.find(user_id)
  user.credits += 100
  user.save!
end

# RIGHT - idempotent
def perform(credit_grant_id)
  grant = CreditGrant.find(credit_grant_id)
  return if grant.processed?
  grant.process!
end
```

## Thin Jobs

```ruby
# WRONG - fat job with business logic
def perform(order_id)
  order = Order.find(order_id)
  order.items.each { |i| i.reserve_inventory! }
  PaymentGateway.charge(order.total, order.payment_method)
  OrderMailer.confirmation(order).deliver_now
end

# RIGHT - thin job
def perform(order_id)
  order = Order.find(order_id)
  PaymentService.call(order: order)
end
```

## Performance

- **Pass IDs, not objects** – `MyJob.perform_later(user.id)` not `perform_later(user)`. Jobs serialize arguments across process boundaries. Models pass objects within synchronous domain code — see @models.
- **Use `find_each`** - Not `all.each`
- **Split large work** – Enqueue individual jobs per record

## Common Mistakes

1. **Non-idempotent operations** – Check state before mutating
2. **Fat jobs** – Move logic to services
3. **Silencing failures** – Avoid broad rescue/discard rules that hide retry-worthy problems.

**Remember:** Jobs are dispatchers, not implementers. Keep them boring and let services own the business flow.
