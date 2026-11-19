# ADR 0016: Authentication, default deny

## Status
Accepted (GH #255; resolves SEC-02 in #240; unblocks #213)

## Context

The app had no login. `/jobs` had optional basic auth and nothing else was protected, which cannot be deployed to a public host (#213). It is a personal tool with one operator, and it mounts two engines (Mission Control at `/jobs`, `ruby_llm-monitoring` at `/monitoring`) next to the app's own controllers.

## Decision

- **Default deny.** `ApplicationController` includes the `Authentication` concern (Rails 8 generator, trimmed), which adds `before_action :require_authentication`. A controller opts out per action with `allow_unauthenticated_access`; only `sessions#new` and `sessions#create` do. The health check `/up` is served by `Rails::HealthController` and stays open. `spec/requests/route_authentication_spec.rb` walks every route, including both engines, and fails if a new route or mount is reachable without a login.
- **Single user, no sign-up, no reset.** `User` (`has_secure_password`, normalised `email_address`) and `Session` (one row per login, signed permanent `session_id` cookie). The user comes from `ADMIN_EMAIL` and `ADMIN_PASSWORD` through the idempotent `bin/rails users:upsert` (also run by `db/seeds.rb` when `ADMIN_EMAIL` is set). A forgotten password is reset by running the task again. The generated passwords controller and mailer are removed: the app has no mailers.
- **Engines use the same gate, not a route constraint.** Mission Control already inherits from `::ApplicationController`; its basic auth is turned off. `ruby_llm-monitoring` 0.4.0 has no `base_controller_class`, so `RubyLLM::Monitoring::ApplicationController` includes `Authentication` in `to_prepare`. A route constraint was rejected: it answers 404 instead of redirecting to the login page. Both engines use `isolate_namespace`, so the concern builds URLs with `main_app.`.
- **Turbo native routes are off** (`config.turbo.draw_routes = false`). turbo-rails draws `/recede_historical_location` and friends on `ActionController::Base`, outside the login, and the app is not a native app.
- **Return-to.** The URL is stored in the Rails session only for a signed-out HTML `GET` outside Turbo frames; login redirects there. A POST cannot be replayed by a redirect, and a JSON fetch or a frame poll (experiments `status_frame`) would overwrite the page the user asked for.
- **Brute force.** `rate_limit to: 10, within: 3.minutes` on `sessions#create`, counted in the controller cache store (a memory store in test; `Rails.cache` stays a null store there).
- **Gmail OAuth keeps working.** The Google redirect back to `oauth_callback` is a cross-site top-level `GET`, and the callback stays behind the login. This relies on two things: the `session_id` cookie is `same_site: :lax` (never `:strict`, which would drop it on that redirect), and login does not call `reset_session`, so `session[:gmail_oauth]` survives a login in the middle of the flow. That is safe because the credential is the signed `session_id` cookie, not the Rails session. `secure` comes from `force_ssl` in production.
- **Hosts.** Production restricts `Host` to `APP_HOST` (comma-separated) when it is set. It is not required at boot, so `assets:precompile` works without env. `/up` is excluded from host authorization.

## Consequences

- Every request and system spec signs in by default (`spec/support/helpers/authentication_helpers.rb`); `:signed_out` opts out.
- There is no session expiry or "sign out everywhere": sessions live until sign-out or until the user is destroyed. Add an expiry to `Session` if that is wanted later.
- Another operator needs another `users:upsert` run per user (the task manages the one user named by `ADMIN_EMAIL`); multi-user management is out of scope.
- A new engine must be mounted with its controllers behind the concern; the route walk fails until it is.
