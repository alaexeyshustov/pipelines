# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

CLASSIFY_EMAILS_OUTPUT_SCHEMA = {
  "type"                 => "object",
  "additionalProperties" => false,
  "required"             => [ "results" ],
  "properties"           => {
    "results" => {
      "type"  => "array",
      "items" => {
        "type"                 => "object",
        "additionalProperties" => false,
        "required"             => [ "id", "tags" ],
        "properties"           => {
          "id"   => { "type" => "string" },
          "tags" => { "type" => "array", "items" => { "type" => "string" } }
        }
      }
    }
  }
}.freeze

# Agent runtime configs — model, tools, and prompt.
# output_schema is set on agents that need reliable structured output (via with_schema).
# When agent.output_schema is present the runner skips wrapping; downstream steps must use
# paths that match the LLM's actual return shape (e.g. "result.ids" for StoreAgent).
#
# IMPORTANT: Keep these configs in sync with AGENT_CONFIGS in
# db/migrate/20260504140000_backfill_agent_configs_from_legacy_classes.rb.
# Seeds cover fresh installs; the migration covers existing installations.
AGENT_DEFINITIONS = {
  "Orchestration::Agents::EmailsClassifier" => {
    model:         LlmModels.emails_agent,
    output_schema: CLASSIFY_EMAILS_OUTPUT_SCHEMA,
    prompt:        <<~PROMPT
      You are an email classifier. Your job is to tag a list of emails by their subject lines and return suggested tags.

      Input:
      {
        "emails": [
          {"id": "id of email", "subject": "Email subject line"}
        ]
      }

      Steps:
      1. For each email, analyze the subject line and suggest short lowercase classification tags that are relevant to the content of the email.
        Tags should be concise and descriptive (e.g. "job", "application", "interview", "offer").
    PROMPT
  },
  "Orchestration::Agents::RecordsNormalizer" => {
    model:  LlmModels.records_agent,
    tools:  [ "Records::ListRowsTool", "Records::ReadRowsTool", "Records::UpdateRowsTool",
              "Records::ReadSchemaTool", "Records::SearchSimilarTool" ],
    prompt: <<~PROMPT
      You are a database record normalizer. Your task is to unify the format of the data in the <destination_table> and propagate known values to records where they are missing.

      Input:
        {
          "records_to_normalize": ["list", "of", "records", "to", "process"],
          "destination_table": "The name of the database table for normalization.",
          "columns_to_normalize": ["list", "of", "columns", "to", "normalize"] (e.g. ["company", "job_title"]),
        }

      A field is considered missing if its value is null, an empty string, "unknown", "n/a", or any other placeholder.

      Steps:
      1. Read the schema of the <destination_table> to understand its structure.
      2. For each record in <records_to_normalize>, for each column in <columns_to_normalize>:
         a. If the field is populated: use search_similar to find all variant spellings of that value in the table.
            Choose the most canonical form among the variants (e.g. shortest non-abbreviated, non-suffixed form).
            (e.g. "Google Inc." → "Google", "SWE" → "Software Engineer").
         b. If the field is missing: look at the record's other populated columns (e.g. company when job_title is missing, or vice versa)
            and call search_similar on those to find sibling records that share the same context and DO have the missing field populated.
            Use the most common or canonical value found among those siblings to fill in the gap.
      3. Update all rows where a normalized or propagated value was determined using update_rows, matching on row ID and updating only the affected columns.
         Skip rows where no new value could be determined.
    PROMPT
  }
}.freeze

# RecordsFiller filled interview rows from ApplicationMail emails, which are gone (GH #215). An agent still used by an
# action is kept (restrict_with_error), so a hand-built pipeline is not broken.
Orchestration::Agent.find_by(name: "Orchestration::Agents::RecordsFiller")&.destroy

# The legacy "Applications Workflow" pipeline was replaced by the Email Ingestion pipeline (ADR 0013).
Orchestration::Pipeline.find_by(name: "Applications Workflow")&.tap do |legacy|
  legacy.pipeline_runs.destroy_all
  legacy.steps.destroy_all
  legacy.destroy!
end

# Nightly full scan of the whitelisted Drive folders (Setting "drive_folder_ids") into tagged Documents.
drive_action = Orchestration::Action.find_or_initialize_by(name: "Sync Drive Documents").tap do |a|
  a.kind        = :service
  a.agent_class = "Orchestration::Executors::DriveDocumentsSync"
  a.save!
end

drive_pipeline = Orchestration::Pipeline.find_or_create_by!(name: "Drive Documents Sync") do |p|
  p.description     = "Scans the whitelisted Google Drive folders and turns new or changed files into tagged Documents."
  p.enabled         = true
  p.cron_expression = "0 3 * * *"
end

if drive_pipeline.steps.empty?
  drive_step = drive_pipeline.steps.create!(name: drive_action.name, position: 1)
  Orchestration::StepAction.create!(
    step: drive_step, action: drive_action, position: 1, output_key: "sync_drive_documents", input_mapping: {}
  )
end

# Email Ingestion (GH #248, ADR 0018): an on-demand pipeline of six steps, loaded from config/pipelines/email_ingestion.json
# (written with Orchestration::PipelineExporter). Fresh databases get it enabled; an existing one is left as the user
# has it, so a later edit or disable survives the next seed run.
#
# The version it replaces had one EmailsSync step on a */30 cron. That pipeline, its runs and its action are removed
# once; another pipeline that still has an EmailsSync step is kept, and logged, because the class no longer exists.
emails_sync_class = "Orchestration::Executors::EmailsSync"
email_ingestion_name = "Email Ingestion"

emails_sync_pipelines = Orchestration::Pipeline.joins(steps: { step_actions: :action })
                                               .where(orchestration_actions: { agent_class: emails_sync_class }).distinct

emails_sync_pipelines.where(name: email_ingestion_name).find_each do |legacy|
  legacy.pipeline_runs.destroy_all # a step action cannot go while action runs refer to it
  legacy.destroy!
end
Orchestration::Action.where(name: "Sync Inbox Emails", agent_class: emails_sync_class).where.missing(:step_actions).destroy_all

emails_sync_pipelines.pluck(:name).then do |names|
  next if names.empty?

  Rails.logger.warn("Pipeline(s) #{names.map(&:inspect).join(', ')} still have a step with #{emails_sync_class}, " \
                    "which no longer exists; they fail when run. Replace the step with the Email Ingestion steps.")
end

unless Orchestration::Pipeline.exists?(name: email_ingestion_name)
  imported = Orchestration::PipelineImporter.call(JSON.parse(Rails.root.join("config/pipelines/email_ingestion.json").read))
  raise "Email Ingestion import failed: #{imported.errors.join('; ')}" if imported.errors.any?

  imported.pipelines.each { |pipeline| pipeline.update!(enabled: true) }
end

# Agents are seeded independently of any pipeline.
AGENT_DEFINITIONS.each do |name, config|
  Orchestration::Agent.find_or_initialize_by(name: name).tap do |a|
    a.model         = config[:model]         if config[:model].present?
    a.tools         = config[:tools]         if config[:tools].present?
    a.prompt        = config[:prompt]        if config[:prompt].present?
    a.output_schema = config[:output_schema] if config.key?(:output_schema)
    a.save!
  end
end

# == Evaluation Datasets per Agent ==

Rails.logger.debug "Seeding Evaluation::Dataset from ActionRun history per agent..."

AGENT_DEFINITIONS.each_key do |agent_name|
  result = Evaluation::DatasetSeeder.call(agent_name: agent_name, sample_size: 20)
  Rails.logger.debug { "Dataset '#{result.agent_name}': #{result.created} created, #{result.skipped} skipped." }
end

# == Tags and Subtags ==

Tag.seed_defaults!

# == Login user ==

# The app sits behind a login; the single user comes from the environment (see lib/tasks/users.rake).
if ENV["ADMIN_EMAIL"].present?
  Rails.application.load_tasks unless Rake::Task.task_defined?("users:upsert")
  Rake::Task["users:upsert"].invoke
end
