# Plan: upload, param and redirect limits (GH #313)

**Status:** implemented | Part of #302 (SEC-14)

## Decisions

- **One home for the sample limit:** `Evaluation::Dataset::SAMPLE_COUNT = 1..50` and `DEFAULT_SAMPLE_COUNT = 20`. The job, the seeder and the wizard view all read them. The view's hard-coded `min: 1, max: 50` and `value: 10` change to the constants, so the UI default becomes 20.
- **Input parsing:** `Integer(value.to_s, 10, exception: false)` (base 10, so `"010"` is 10, not octal 8). A result of nil means the default; anything else is clamped to `SAMPLE_COUNT`.

  | input | `"0"`, `"-5"` | `"abc"`, `""`, nil, `"10.5"` | `"10000"` |
  |---|---|---|---|
  | result | 1 | 20 | 50 |

  The same table applies to `generate`, `resync` and the rake task.
- **`generate`:** the clamp lives in `SyntheticDatasetJob#perform`, so it also covers jobs already queued with raw strings. The controller doesn't clamp, but it filters its params through `params.permit(:draft_token, :agent_name, :dataset_name, :count, :hints)`.
- **`hints`:** `hints.to_s.truncate(MAX_HINTS_LENGTH)` with `MAX_HINTS_LENGTH = 1000` on the job.
- **`resync`:** the controller passes `Integer(params[:count].to_s, 10, exception: false)`, which is an Integer or nil. `DatasetSeeder` turns nil into the default and clamps to the range. Its `sample_size` becomes `Integer?`.
- **Rake task is capped too.** `rake evaluation:seed_dataset[Agent,200]` seeds 50. `lib/evaluation/tasks.rb` parses the same way, and the seeder clamps.
- **`agent_name` / `dataset_name` (generate):**
  - The job raises `ArgumentError, "Unknown agent: …"` unless `Evaluation::Prompt.exists?(name: agent_name)`. That is the same list the wizard's step 1 offers. The existing rescue sets the draft to `error`.
  - `Evaluation::Dataset` adds `validates :name, length: { maximum: 255 }`, so `create!` fails and the draft shows the error.
- **Dead resync branch removed.** `SyntheticDatasetJob`'s `dataset_id:` keyword, `persist_results`'s branch and `resync_dataset` go. Nothing enqueues them; resync goes through `DatasetSeeder`.
- **Import form:**
  - Validators run in this order: `file_present`, `file_is_upload`, `file_within_size_limit`, `file_is_json_object`. The JSON validator starts with `return if errors.include?(:file)`.
  - `file_is_upload` is a duck-type check: `respond_to?(:read) && respond_to?(:size)`.
  - `MAX_BYTES = 1.megabyte`.
  - `payload` reads `@file.read(MAX_BYTES + 1)`, so even a dishonest `size` can't cause an unbounded read.
- **Zip entries:** `Document::TextExtractor#docx_xml` reads `get_input_stream.read(MAX_DOCX_XML_BYTES + 1)` and raises `Unsupported` if the result is bigger than the limit. The `entry.size` check stays as the fast path, but that value comes from the zip header and can lie.
- **`toggle`:** `redirect_back_or_to orchestration_pipeline_path(@pipeline)`.

## Steps

1. **Import form** (`app/forms/orchestration/pipeline_import_form.rb`, sig `_Upload` gains `size`).
   - Red: `spec/forms/orchestration/pipeline_import_form_spec.rb`
     - an upload of `MAX_BYTES + 1` bytes is invalid, with a size error and no JSON error;
     - a String, a Hash and an Array `file` are each invalid with no exception.
   - Request spec: `POST` with a String `file` returns a redirect with an alert, not a 500.
2. **Sample limit**
   - Constants on `Evaluation::Dataset` and the name length validation.
   - Seeder clamp and default.
   - Controller `resync` parsing and `permit`.
   - Rake parsing.
   - View uses the constants.
   - Red specs:
     - the seeder with nil, 0, -5, 10000;
     - a `resync` request with each value in the table;
     - `rake evaluation:seed_dataset` with `abc` and 200;
     - the model's name length.
3. **Job** (`app/jobs/evaluation/synthetic_dataset_job.rb`, sig: `count: Integer | String | nil` at `perform`, `Integer` in `build_user_message`, `dataset_id` removed).
   - Red: the prompt holds the clamped count for each value in the table; `hints` of 1500 chars is cut to 1000; nil `hints` works; an unknown agent sets the draft to `error`; the `dataset_id` context is removed.
   - Red: a `generate` request with `hints[a]=x` returns 200, not 422 (`hints[]=x` already works).
   - Size and zip errors say "too large".
4. **Zip bound** (`app/services/document/text_extractor.rb`).
   - Red: a docx whose `word/document.xml` inflates past the limit while its header claims a small size raises `Unsupported`.
5. **Toggle** (`app/controllers/orchestration/pipelines_controller.rb`).
   - Red: request specs for an external Referer, a `//evil.example` Referer, no Referer (each redirects to the pipeline) and a same-host Referer (redirects back).

## Checks

Definition of done from `AGENTS.md`. No JS changes, so the pnpm checks are only needed if the view change trips `herb:lint`.
