# Plan: harden email connector settings and Gmail OAuth (GH #300)

**Status:** planned, architect- and critique-reviewed | **Branch:** `fix/gh-300-connector-hardening` | **Parent:** #240 (SEC-04, SEC-05)

## Decisions

- **No data migration** (user's call). No `EmailConnector` rows exist, so `encrypts :configuration` needs only keys.
- **Encryption keys.**
  - Dev and prod read `active_record_encryption` from credentials.
    - `config/master.key` is missing.
    - Nothing reads credentials today, so the user regenerates `config/credentials.yml.enc` and runs `bin/rails db:encryption:init`.
    - Prod sets `RAILS_MASTER_KEY`.
  - Test gets fixed, non-secret keys in `config/environments/test.rb`, so CI never needs the master key. Without them, every `EmailConnector` read or write raises in specs.
  - Non-deterministic encryption: nothing queries by `configuration`.
  - Document the setup in `docs/claude/gotchas.md`.
- **Gmail tokens stay in files** (user's call).
  - The path comes from server config (`GMAIL_CREDENTIALS_PATH` and `GMAIL_TOKEN_PATH`, falling back to `Rails.root`), never from a request.
  - An encrypted DB token store (a custom `Google::Auth::TokenStore`) goes to a separate ticket.
    - Runtime adapters come from `ProviderRegistry#auto_load` → `GmailAdapter.from_env` and never read `EmailConnector` rows.
    - `lib/emails` (infra) can't reference domain models.
    - That ticket gets an ADR for injecting the store from above.
  - Known limit until then: every Gmail connector shares one token file.
- **Permitted configuration per provider.**
  - Gmail: **no keys**. Syncing filtered by label is not intended (user's call).
  - Yahoo: `username` and `password`.
  - The controller permits the union (`configuration: [:username, :password]`).
  - `EmailConnector` keeps `ALLOWED_CONFIGURATION` and slices in `before_validation`, which also drops stale keys when the provider changes.
  - No form object: `.agents/rules/form_objects.md` scopes forms to multi-model writes, and `Archspec.rb` bars forms from `Emails`.
- **Update merges, it doesn't replace.**
  - Today every edit-form field renders blank: `configuration&.dig(:password)` on a string-keyed hash returns nil. Saving the form unchanged therefore wipes the stored username and password.
  - The model merges the permitted keys into the stored configuration and keeps the password when it's blank.
  - The form reads string keys, shows the stored username, and never renders the password (`value:` removed).
- **The Yahoo IMAP host and port are fixed in infra.**
  - `YahooAdapter::IMAP_HOST` (`imap.mail.yahoo.com`) and `IMAP_PORT` (993). An env override is acceptable as server config.
  - Remove the host and port form fields and the `host:`/`port:` passthrough in `ConnectionTester`.
  - No allowlist: there's only one IMAP provider.
  - net-imap 0.6.8 already defaults to a 30s `open_timeout` and VERIFY_PEER with a hostname check. `ImapSession` makes both explicit, with a shorter timeout. The PR says so; it isn't a closed hole.
- **The web OAuth `state` is hand-rolled in the controller, not `WebUserAuthorizer`** (architect).
  - `WebUserAuthorizer` takes a `Rack::Request` (web concerns in infra), compares with `!=`, and builds its own callback flow.
  - `setup` (POST) stores `session[:gmail_oauth] = { connector_id:, state: SecureRandom.urlsafe_base64(32) }`.
  - `GmailAuth#authorization_url(callback_uri:, state:)` passes it to `UserAuthorizer#get_authorization_url`.
  - `oauth_callback` deletes the session entry first, then:
    - compares with `ActiveSupport::SecurityUtils.secure_compare`;
    - rejects a missing or wrong `state`;
    - handles Google's `error=`.
- **SEC-04.4 shrinks** (user agreed). `078617cc` already made `GmailAuth#credentials` non-interactive by default, and `spec/lib/emails/gmail_auth_spec.rb:42` covers it. What's left is the CLI loopback:
  - `IO.select` timeout before `accept`; raise a named error and close the server in `ensure`. The timeout is injected through the constructor.
  - A random `state` per run, checked in `accept_oauth_callback` next to `code`.
- **Token files are written 0600 in `GmailAuth#build_authorizer`** (architect).
  - `FileTokenStore` → `PStore` opens the file with the umask and rewrites in place, keeping the existing mode. googleauth also rewrites the file on every refresh.
  - So: create the file with `0o600` and `chmod` it before building the store. This also covers the Drive token.
  - Don't touch `File.umask`.
- **Gmail paths reach the controller through a public infra API.**
  - `GmailSession.paths_from_env` is private, so expose `GmailSession.auth_from_env`, which returns a `GmailAuth`.
  - Drop the `opts[:credentials_path]`/`opts[:token_path]` overrides; `ConnectionTester` is their only caller.
  - The controller rescues `Emails::NotConfigured`, which also fixes today's unrescued `TypeError` on nil paths.
  - `GmailSession.reset` deletes the configured token path, not a hard-coded `Rails.root/token.yaml`.
- **Generic errors in flash, details in the log.**
  - `ConnectionTester#call` returns `{ success: false, error: GENERIC, exception: e }`.
  - `TestConnectionService` logs the exception, and `oauth_callback` does the same.
  - This removes the file-existence oracle (`Missing Gmail credentials file … #{path}`) and the `e.message` echo.
- **The `oauth_callback` rescue doesn't assume a connector.** If `find` raises (connector deleted), it redirects to the index; today `edit_settings_email_connector_path(nil)` raises and returns a 500.
- **`filter_parameters` gets `:configuration`** (user's call).
  - Request logs are filtered today only by accident: `:email` partially matches `email_connector`.
  - `EmailConnector#inspect` prints the Yahoo password in plaintext (verified).
  - `encrypts` auto-adds the attribute to the filters too. Keep the explicit entry; the `inspect` spec guards either way.
- **Remove `show`** (user's call). The route exists, `def show; end` has no view, and nothing links to it: `GET` returns `MissingExactTemplate`.
  - Use `resources :email_connectors, except: :show`.
  - Remove the action and its `before_action` entry.

## Steps

### 1. Encryption and filtering (SEC-05)
- **Files:** `app/models/email_connector.rb` (domain), `config/environments/test.rb`, `config/initializers/filter_parameter_logging.rb`, `docs/claude/gotchas.md`.
- **Red first:** `spec/models/email_connector_spec.rb`:
  - the raw `configuration` column (`connection.select_value` or `ciphertext_for(:configuration)`) doesn't contain the password;
  - `inspect` doesn't contain the password;
  - the configuration round-trips through a reload.
- **Done when:** `encrypts :configuration` is declared after `serialize` and the specs pass without a master key.

### 2. Permitted configuration and merge-on-update (SEC-04.1, SEC-05)
- **Files:**
  - domain: `app/models/email_connector.rb`;
  - interface: `app/controllers/settings/email_connectors_controller.rb`, `app/views/settings/email_connectors/_form.html.erb`;
  - sigs.
- **Red first:**
  - Model spec:
    - Gmail drops every key;
    - Yahoo keeps only `username` and `password`;
    - a provider change drops stale keys;
    - a blank password on update keeps the stored one.
  - Request spec:
    - a submitted `credentials_path`, `token_path`, `host` or `port` is not stored;
    - the edit form shows the stored username and has no `value` on the password input;
    - an update without a password keeps both the username and the password.
- **Done when:** the Gmail form has no configuration fields, and the Yahoo form has only username and password.

### 3. Gmail paths from server config (SEC-04.1)
- **Files:**
  - infra: `lib/emails/adapters/gmail_session.rb`, `lib/emails/connection_tester.rb`;
  - interface: the controller;
  - `bin/pipeline` if needed, and sigs.
- **Red first:**
  - `gmail_session_spec`:
    - `auth_from_env` uses ENV paths and ignores opts;
    - `reset` deletes `GMAIL_TOKEN_PATH`.
  - `connection_tester_spec`: config paths are no longer forwarded (update `:64-70`).
  - Request spec: `setup` without a credentials file redirects with a generic alert and no path in the body. This replaces "shows a helpful error message".
- **Done when:** no path in the request or the row reaches `GmailAuth`.

### 4. POST setup, web `state`, callback errors, remove `show` (SEC-04.3)
- **Files:**
  - `config/routes.rb`;
  - interface: the controller, `_form.html.erb`, `edit.html.erb`;
  - infra: `lib/emails/gmail_auth.rb`;
  - sigs, including `sig/lib/emails/gmail_auth.rbs`.
- **Red first:** request spec:
  - `GET setup` and `GET show` aren't routable;
  - `POST setup` redirects to Google with a `state` that matches the session;
  - `oauth_callback`:
    - a missing or wrong `state` is rejected and `exchange_code` isn't called;
    - a correct `state` exchanges the code and clears the session;
    - Google's `error=` gets a generic alert;
    - a deleted connector redirects to the index.
  - The "Connect Gmail" `button_to` isn't nested inside the update form.
  - Rewrite the existing `GET setup` specs and the session seeding.
  - CSRF: `test.rb` disables forgery protection, so one spec turns it on to show that a POST without a token is rejected.
- **Done when:** these specs pass and the button sits outside `form_with` (in `edit.html.erb`).

### 5. Generic connection errors (SEC-04.2)
- **Files:** infra: `lib/emails/connection_tester.rb`; application: `app/services/emails/test_connection_service.rb`; the controller.
- **Red first:**
  - `connection_tester_spec`: on failure it returns the generic error and the exception.
  - `test_connection_service_spec`: the exception is logged and the result carries the generic message.
  - Request spec: the flash is generic. Update the `"Connection failed: boom"` expectation.
- **Done when:** no exception message reaches the flash.

### 6. Fixed IMAP endpoint (SEC-04.2)
- **Files:** infra: `lib/emails/adapters/yahoo_adapter.rb`, `lib/emails/adapters/imap_session.rb`, `lib/emails/connection_tester.rb`; sigs.
- **Red first:**
  - `connection_tester_spec`: a `host` or `port` in the configuration is ignored, and `IMAP_HOST`/`IMAP_PORT` are used. Update `:48-53`.
  - `imap_session_spec`: `Net::IMAP.new` receives `open_timeout:` and `ssl: { verify_mode: VERIFY_PEER }`.
  - `yahoo_adapter_spec`: an empty host can't come in from the request.
- **Done when:** no request input chooses the IMAP endpoint.

### 7. `GmailAuth` token mode, CLI timeout, CLI `state` (SEC-04.4, SEC-05)
- **Files:** infra: `lib/emails/gmail_auth.rb`; `sig/lib/emails/gmail_auth.rbs`.
- **Red first:** `gmail_auth_spec`, with a real temp dir:
  - after `exchange_code`, the token file mode is `0600`;
  - an existing `0644` file becomes `0600`;
  - the loopback `accept` times out, raises a named error and closes the server;
  - a callback with a wrong or missing `state` raises, and one with the right `state` returns the code.
- **Done when:** these specs pass and the existing non-interactive spec stays green.

### 8. Docs and issues
- `docs/claude/gotchas.md`: master key and encryption-key setup.
- Tick the #300 scope items, open the DB token-store ticket, and mark #240 SEC-04 and SEC-05 as resolved.

## Checks

- `COVERAGE=true bundle exec rspec`
- `bundle exec rubocop`; `bundle exec archspec check --check-todo`; `bundle exec archspec reflect` (`EmailConnector` changes)
- `bundle exec rbs -r optparse validate`, `bundle exec steep check`, `bundle exec bin/rbs_audit coverage --threshold=90`
- `bundle exec rigor check`
- `bundle exec brakeman --no-pager`

## Open questions

None. The user settled all of them:
- no data migration;
- tokens stay in files, and the DB token store is a follow-up;
- Gmail has no configuration keys, because syncing filtered by label is not intended;
- `show` is removed;
- `:configuration` is added to `filter_parameters`.
