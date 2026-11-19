# Plan: gist and CSV export hardening (GH #311)

**Status:** planned | Part of #302 (SEC-08, SEC-10)

## Decisions

- **CLI CSV `id` column: drop it. No `columns:` keyword.**
  - Both entry points write `interviews.csv` to the same `GIST_ID`. Today the web export leaves `id` out and the CLI keeps it, so the gist's columns flip depending on who wrote last. Dropping `id` makes the file the same either way.
  - `id` is a local primary key and means nothing outside this app's database.
  - A `columns:` option would add an API, a sig and mutant targets that only one caller uses.
  - Side effect: the CLI's row order becomes `applied_at desc` (the service's order). This is accepted and recorded in the docs.
- **Id check happens in `GistUploader#initialize`.** It raises `GistUploader::InvalidGistId < ApiError`, so the check runs before any request and also covers `from_env`. Because it is an `ApiError`, the service's rescue and the CLI's existing `rescue GistUploader::ApiError` both handle it without changes.
- **Blank id means nil.** `@gist_id = gist_id.presence`. The README tells users to set `GIST_ID=` (empty), and dotenv turns that into `""`, which is truthy. Only an id that isn't blank is checked against `/\A[a-f0-9]{1,64}\z/i`.
- **Public check.** On the update path, `GET /gists/:id` comes first. If `public` is `true`, it raises `ApiError, "Refusing to update public gist"` and the `PATCH` is never sent. The create path makes no `GET`.
- **Headers.** `X-GitHub-Api-Version: 2022-11-28` moves into `GistUploader#build_http_request` (it is currently only in `GistExportService`). `GET` requests have no body.
- **`GistExportService.call(ids:)`** reads `ENV["GITHUB_TOKEN"]` and `ENV["GIST_ID"]` itself and takes no `gist_id:` keyword.
  - A blank `GIST_ID` gives a failed `Result` ("GIST_ID is not configured."). The web flow never creates a gist; create mode stays CLI-only.
  - It rescues `GistUploader::ApiError` into `Result(ok: false, message: e.message)`.
  - It keeps the existing message "Interviews exported to gist <id>.".
- **Executor.** Remove the `input_schema(...)` call entirely, the same way `DriveDocumentsSync` has none. Keep `**_kwargs` so stored step inputs that still pass `gist_id` are ignored rather than raising. Keep its own "GIST_ID not configured → skipped" check.
- **Sanitising.** `CsvExportService` adds a private `sanitize(value)`. Strings matching `/\A[=+\-@\t\r]/` get a `'` prefix. Anything else (nil, Date) is left alone. The header row is not sanitised.
- **JSON errors.** Out of scope: `GistUploader#request` lets `JSON::ParserError` through on a body that isn't JSON. That is an unexpected failure, so raising is correct under `.agents/rules/services.md`.

## Steps

### 1. Harden `GistUploader` (application: `app/services/gist_uploader.rb`)
- **Red first:** `spec/services/gist_uploader_spec.rb`, WebMock with no stubs for the invalid cases:
  - `../user`, `abc\n123`, a 65-char id, and an id with a non-hex letter each raise `InvalidGistId` from `new`, with no request made.
  - `""` goes down the create path.
  - An uppercase hex id is accepted.
  - On update, `GET` with `public: false` is followed by a `PATCH`.
  - With `public: true`, it raises and `PATCH` is not requested.
  - Every request carries `X-GitHub-Api-Version`.
  - Create sends no `GET`.
  - Replace the fixture id `gist_42` with `abc123` (including `.from_env`).
- **sig:**
  - Add `GIST_ID_FORMAT`, `InvalidGistId < ApiError`, `API_VERSION`.
  - Add private `validate_id` and `ensure_secret!`.
  - `request` body becomes optional.
  - `build_http_request` returns `Net::HTTP::Get | Net::HTTP::Post | Net::HTTP::Patch`.
- **Accept:** the spec is green. Once step 2 is done, grepping `app/ lib/` for `/gists/` matches only `gist_uploader.rb`.

### 2. Make `GistExportService` delegate (application: `app/services/interviews/gist_export_service.rb`)
- Delete `GITHUB_API_URI`, `patch_gist`, `build_error_result`, `parse_error_body` and `require "net/http"`.
- **Red first:** the service spec uses `.call(ids:)` and stubs `ENV["GIST_ID"]`. It covers:
  - Token missing → failure, no HTTP.
  - `GIST_ID` blank → failure, no HTTP.
  - Success through the cassette.
  - Not found through the cassette, with a message that includes "Not Found".
  - A public gist → failed `Result`, no `PATCH`.
  - An invalid `GIST_ID` (`../user`) → failed `Result`, no HTTP.
- **Cassettes:**
  - `success.yml`: add a first `GET /gists/abc123` returning `"public":false`. Change the `PATCH` body to the header row without `id`.
  - `not_found.yml`: change it to a `GET /gists/deadbeef` returning 404, with no `PATCH`.
- **sig:** `call` and `initialize` take `(ids: ...)`. Remove `@gist_id`, `GITHUB_API_URI` and the private HTTP methods.
- **Accept:** the service spec is green, and `git grep Net::HTTP app/services/interviews` is empty.

### 3. Web flow uses ENV only (interface: `interviews_controller.rb`, `interviews/index.html.erb`)
- `export_gist` becomes `Interviews::GistExportService.call(ids: params[:ids])`.
- Remove the `gist_id` label and input from the dialog. Replace them with a short line of text: "Exports to the gist configured in GIST_ID." Verify the dialog slot still has a body.
- **Red first:** `spec/requests/interviews_spec.rb`:
  - `GIST_ID` unset → alert includes "GIST_ID".
  - `GIST_ID=abc123` → success notice.
  - Posting `gist_id: "deadbeef"` while `GIST_ID=abc123` still hits `abc123`.
  - Not found with `GIST_ID=deadbeef`.
- **Accept:** `git grep gist_id app/controllers app/views` is empty.

### 4. Remove `gist_id` from the executor (application: `lib/orchestration/executors/interviews_gist_exporter.rb`)
- **Red first:**
  - `input_schema` is `nil`.
  - `call(gist_id: "abc123")` with `GIST_ID` unset → skipped.
  - With ENV set (`abc123`), it calls `GistExportService.call(ids: nil)`.
  - Unset → skipped.
- **sig:** remove `@gist_id`. `call` and `initialize` take `**untyped`.
- **Accept:** `git grep gist_id lib/` is empty.

### 5. CSV sanitising and CLI reuse (`csv_export_service.rb`; `bin/pipeline`)
- **Red first:**
  - `csv_export_service_spec.rb`: each of `= + - @ \t \r` at the start of `company` / `job_title` gets a `'` prefix. `"A=B"` and `"Acme"` are unchanged. nil dates stay nil.
  - `interviews_spec.rb`: the batch `export` CSV with a company of `=HYPERLINK(...)` has the `'` prefix.
  - `upload_gist_spec.rb`:
    - `gist_42` becomes `abc123`, with a `GET` stub for `public:false`.
    - The uploaded content has no `id` header, and a `=cmd` company is prefixed.
    - With no id and `GIST_ID=""`, it creates the gist with `public: false`.
    - `--gist_id ../x` prints "Upload failed: ..." with no HTTP.
- In `bin/pipeline`, `interviews_csv` becomes `Interviews::CsvExportService.call(ids: nil).csv`.
- **sig:** add `FORMULA_PREFIX` and private `sanitize: (String | Date | nil) -> (String | Date | nil)`.
- **Accept:** `bin/pipeline` contains no `CSV.generate`.

### 6. Docs
- `README.md:60` and `docs/connectors.md:42-50`:
  - The web and orchestration exports use only `GIST_ID` and refuse public gists.
  - The id must be hex.
  - The CLI's `--gist_id` overrides it, and the CLI can still create a gist.
  - The CSV has no `id` column and cells that could be formulas are prefixed with `'`.
- Mark SEC-08 and SEC-10 in #240 once the PR merges.

## Checks

- `COVERAGE=true bundle exec rspec`. At risk: VCR cassettes (the new `GET`) and `ENV` stubs (`allow(ENV).to receive(:[]).and_call_original`).
- `bundle exec rubocop` and `bundle exec archspec check --check-todo`. There are no new dependency edges, so `archspec reflect` is not needed.
- `bundle exec rbs -r optparse validate`, `bundle exec steep check`, `bundle exec bin/rbs_audit coverage --threshold=90`. At risk: the `Net::HTTP::Get` union and the new private methods.
- `bundle exec rigor check`.
- `bundle exec brakeman --no-pager`.
- No JS changes.
- Mutant (CI only) will target the regex anchors, the `i` flag, `{1,64}`, `presence` and each sanitiser character. The red specs above cover each one.

## Resolved questions

- **Dialog body:** a static line of text ("Exports to the gist configured in GIST_ID."), with no id shown.
- **CLI row order:** `applied_at desc` is accepted.
