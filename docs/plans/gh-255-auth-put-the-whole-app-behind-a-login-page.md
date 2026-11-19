# Plan: put the whole app behind a login page (GH #255)

**Status:** planned, architect- and critique-reviewed | **Branch:** `feat/gh-255-auth-put-the-whole-app-behind-a-login-page` | **Parent:** #240 (SEC-02), blocks #213

## Decisions

- **Generator, then trim.** Run `bin/rails generate authentication`. Delete `PasswordsController`, `PasswordsMailer`, `app/views/passwords/`, `resources :passwords`, and the mailer files it creates (`ApplicationMailer`, `layouts/mailer.*`). The app has no mailers today. Delete any generated `test/` files; specs are written by hand.
- **One gate for app and engines.** `ApplicationController` includes `Authentication`. Mission Control already inherits from `::ApplicationController` by default. `/monitoring` gets `RubyLLM::Monitoring::ApplicationController.include Authentication` inside the existing `to_prepare`, because gem 0.4.0 has no `base_controller_class`. There is no route constraint: it would return 404, not a redirect to login.
- **Engine-safe URLs.** The concern uses `main_app.new_session_url` and `main_app.root_url`, because both engines use `isolate_namespace`.
- **Return-to.** `session[:return_to_after_authenticating]` is stored only when `request.get? && !turbo_frame_request?`, so the experiments `status_frame` poll can't overwrite it. There is no `reset_session` on login, which keeps `session[:gmail_oauth]` alive. This is safe because the login credential is the signed `session_id` cookie, not the Rails session. `oauth_callback` stays behind login.
- **Cookies.** Keep the generator's `httponly: true, same_site: :lax` (never `:strict`, or the Google redirect back would lose the cookie). `secure` comes from `force_ssl` in production; there is no unconditional flag.
- **Turbo native routes.** `config.turbo.draw_routes = false` in `config/application.rb`. turbo-rails 2.0.23 draws `/recede_historical_location`, `/resume_historical_location` and `/refresh_historical_location` on `ActionController::Base`, outside the login check. The app isn't a native app, and this keeps the allowlist down to `/up` plus `sessions#new` and `sessions#create`.
- **Hosts.** Set `config.hosts` from `APP_HOST` (comma-split) only when it is set. Don't raise when it's unset, because `assets:precompile` runs without env. Uncomment the `host_authorization` `/up` exclusion (`production.rb:68`). Leave `ssl_options` commented out (`production.rb:31`): with `assume_ssl` true, `force_ssl` never redirects `/up`.
- **Single user.** An idempotent `users:upsert` task in `lib/tasks/users.rake` (application layer) reads `ADMIN_EMAIL` and `ADMIN_PASSWORD` and never prints the password. `db/seeds.rb` runs it only when `ADMIN_EMAIL` is set. There is no sign-up and no reset; a reset is `bin/rails users:upsert` or the console.
- **Nav.** `UI::LegacySidebarComponent.new(current_path:, user:)`: both layouts (`application`, `mission_control/jobs/application`) pass `Current.user`. The component shows the email and a `button_to "Sign out", helpers.main_app.session_path, method: :delete` when `user` is present. This follows App/NoCurrentInComponent.
- **Contracts pinned by the red specs:**
  - routes: `resource :session, only: %i[new create destroy]` (no show, edit or update routes)
  - form fields `email_address` and `password`, and a "Sign in" button
  - the rate-limited alert is exactly "Try again later."
  - the sign-out form posts to `/session` with `_method=delete`
  - the route walk also excludes `/_system_test_entrypoint` (ViewComponent, test env only)
  - remove the TODO guard `AuthenticationHelpers.available?` in `spec/support/helpers/authentication_helpers.rb` once the feature works
  - switch the string `describe "User"`/`"Session"` to the constants
- **Login view.** Plain ERB `sessions/new.html.erb` in a bare `layouts/sessions.html.erb` with no sidebar. It reuses `UI::FlashComponent` for the error and adds no new component.

## Steps

### 1. Models, migrations, bcrypt, user task (one commit)

- Files:
  - `Gemfile` (bcrypt), `Gemfile.lock`, `rbs_collection.lock.yaml`
  - migrations, `db/structure.sql`
  - `app/models/user.rb`, `session.rb`, `current.rb` (**domain**)
  - `lib/tasks/users.rake` (**application**)
  - `sig/app/models/{user,session,current}.rbs`, plus `has_secure_password` and `authenticate_by` in `sig/shims/activerecord.rbs`
  - `spec/factories/users.rb`, `spec/factories/sessions.rb`
  - `archspec_facts/rails.yml` (`archspec reflect`)
  - `db/seeds.rb`
- Red first:
  - `spec/models/user_spec.rb`: email normalized, `authenticate_by` true/false, `has_many :sessions, dependent: :destroy`
  - `spec/models/session_spec.rb`
  - `spec/tasks/users_upsert_spec.rb` via `RakeTaskHelpers`: creates once, rerun updates the password without duplicating, fails clearly when an env var is missing, output never contains the password
- Accept: specs green; `steep check` clean for `app/models`; `archspec reflect` diff contains only User and Session; `bundle exec ruby script/rigor_schema.rb` rerun and `rigor check` clean.

### 2. Default-deny, login and logout, rate limit, spec helpers (one commit, so the suite stays green)

- Files:
  - `app/controllers/concerns/authentication.rb`, `app/controllers/sessions_controller.rb`, `app/controllers/application_controller.rb` (include the concern first, before `before_action :filters`) (**interface**)
  - `app/views/sessions/new.html.erb`, `app/views/layouts/sessions.html.erb`
  - `config/routes.rb` (`resource :session`; no passwords)
  - `config/environments/test.rb` (`config.action_controller.cache_store = :memory_store`; `Rails.cache` stays `:null_store`)
  - `spec/support/helpers/authentication_helpers.rb`:
    - `before(type: :request)` clears `ActionController::Base.cache_store`, then signs in with a real `post session_path` unless the example has `:signed_out` metadata
    - `before(type: :system)` signs in through the login form, for both rack_test and Cuprite
  - existing request specs touched only where they assumed no auth
- Red first:
  - `spec/requests/sessions_spec.rb` (`:signed_out`): login succeeds and sets the session cookie; wrong password redirects to login with an alert; the 11th wrong POST within 3 min is rate-limited; DELETE logs out and a later GET redirects to login
  - `spec/requests/authentication_spec.rb` (`:signed_out`): a GET stores return-to and login lands there; a POST and a Turbo frame request (`Turbo-Frame` header) don't store it
  - in `spec/requests/settings/email_connectors_spec.rb`, an OAuth context:
    1. POST setup
    2. `Session.delete_all`
    3. GET callback (code, state) redirects to login
    4. POST session redirects back to the callback URL
    5. follow it: token exchange happens (existing WebMock stub) and the connector is connected
- Accept: the whole `rspec` suite passes; there are no stubs (App/NoTestDoubles); `herb` lint and analyze are clean for the new ERB.

### 3. Engines and the route-walk spec

- Files:
  - `config/initializers/mission_control.rb`: `http_basic_auth_enabled = false` unconditionally; delete the credentials block and the stale comment; keep the adapter lines
  - `config/initializers/ruby_llm_monitoring.rb`: add the `include Authentication` inside `to_prepare`
  - `config/application.rb`: `config.turbo.draw_routes = false`
  - `spec/requests/jobs_dashboard_spec.rb`: signed in gets 200; `:signed_out` redirects to login
- Red first, `spec/requests/route_authentication_spec.rb` (`:signed_out`):
  - Walk `Rails.application.routes` plus the `RubyLLM::Monitoring::Engine` and `MissionControl::Jobs::Engine` route sets, prefixed with their mount paths.
  - Fill dynamic segments with dummies (`:id` → `1`, `:status` → `failed`, `:application_id` → `x`).
  - Every verb expects a redirect to `new_session_url`. POST, PATCH, PUT and DELETE also expect no stored return-to.
  - Allowlist: `/up`, `sessions#new`, `sessions#create`. Exclude `/rails/view_components`.
  - Fail on any mount the walk doesn't cover.
- Accept: the spec passes with and without `CI=1` (eager load); `/monitoring` and `/jobs` both redirect, neither returns 404 or 401.

### 4. Nav sign-out, system spec, Playwright login

- Files:
  - `app/components/ui/legacy_sidebar_component.{rb,html.erb}` (**interface**)
  - `spec/components/previews/ui/legacy_sidebar_component_preview.rb` (unsaved `User.new(email_address:)`)
  - both layouts
  - `e2e/auth.setup.ts`: runs `users:upsert` with `RAILS_ENV=test`, logs in, saves `storageState`
  - `playwright.config.ts`: a `setup` project the others depend on
  - `e2e/pipeline-export-import.spec.ts`: already broken on `main`. It still targets the `Applications Workflow` pipeline, which #228 removed from the seeds. Repoint `PIPELINE`/`STEP_COUNT` to a pipeline that `db/seeds.rb` still creates (`Email Ingestion` or `Drive Documents Sync`). Also add `Subtag` and `Tag` (and any other models `db:seed` creates) to `RESET`: `Tag.seed_defaults!` rows survive the run and break about 150 RSpec examples on the shared local test DB ("Name has already been taken").
  - `.github/workflows/ci.yml`: a new `playwright` job, `timeout-minutes: 5`.
    - Setup is the same as the `e2e` job: Ruby, `db:schema:load`, Node, pnpm, asset build.
    - Install the browser with `pnpm exec playwright install --with-deps chromium`, and cache `~/.cache/ms-playwright` keyed on the `@playwright/test` version.
    - Run `pnpm e2e` (chromium project only; `screenshots` only captures images and has no assertions).
    - Upload `tmp/playwright/report` as an artifact when the job fails.
- Red first:
  - `spec/components/ui/legacy_sidebar_component_spec.rb`: renders the email and a sign-out button when `user:` is given, and neither when it's nil
  - `spec/system/sign_in_spec.rb` (`:signed_out`): fill in the form, reach the dashboard (`root`, sidebar visible), sign out, back on the login page
- Accept: rubocop clean (NoCurrentInComponent, ComponentMustHavePreview); `pnpm e2e` passes locally with `CI=1` and no retries used; the new `playwright` CI job is green in under 5 minutes; `pnpm lint` and `pnpm format:check` clean.

### 5. Production config and env example

- Files:
  - `config/environments/production.rb`: hosts from `APP_HOST`; `host_authorization` `/up` exclusion
  - `.env.docker.example`: drop `JOBS_DASHBOARD_*`; add `APP_HOST`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`
- Accept:
  - `RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile` succeeds with no `APP_HOST`
  - `APP_HOST=a.example,b.example` makes `Rails.application.config.hosts` include both
  - `git grep JOBS_DASHBOARD` finds nothing
  - `brakeman` clean

### 6. Docs

- Files:
  - `docs/adr/0016-authentication-default-deny.md`: default-deny; single user with no sign-up and no reset; engines gated by the shared concern, and why not a route constraint (404 instead of a redirect); OAuth relies on `same_site: :lax` and on no `reset_session`
  - `docs/architecture.md`: a short "Authentication" section
- Accept: the docs link to the ADR. On GitHub: tick the #255 scope items and mark #240 SEC-02 as resolved.

## Checks

- `COVERAGE=true bundle exec rspec`, and the route-walk spec again with `CI=1`
- `bundle exec rubocop`; `bundle exec archspec check --check-todo` (`archspec_todo.yml` unchanged)
- `bundle exec archspec reflect` in step 1 (models and Gemfile change, ADR 0011); commit `archspec_facts/`
- `bundle exec rbs collection install` (bcrypt); `bundle exec rbs -r optparse validate`; `bundle exec steep check`; `bundle exec bin/rbs_audit coverage --threshold=90`
- `bundle exec ruby script/rigor_schema.rb` (`db/structure.sql` changed), then `bundle exec rigor check`
- `bundle exec brakeman --no-pager`
- `pnpm herb:lint`; `bundle exec herb analyze .`
- `pnpm lint`; `pnpm format:check` (e2e TS changed)

## Resolved questions

- **Session lifetime:** keep the generator's permanent signed `session_id` cookie. No expiry on `Session`.
- **Playwright in CI:** add it in this branch (step 4). A local run of every project takes 49s, and about 20s once the stale spec is fixed (it sits on a 30s timeout). Installing Chromium takes 121s cold. The job is well under the 5-minute budget, and `timeout-minutes: 5` enforces it.
