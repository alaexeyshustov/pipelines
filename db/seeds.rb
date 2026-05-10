# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# == Applications Workflow Pipeline ==
#
# Mirrors Pipeline::ApplicationsWorkflow steps 1-8, plus two IngestionExecutor steps for fan-in joins.

FILTER_EMAILS_OUTPUT_SCHEMA = {
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

STORE_EMAILS_OUTPUT_SCHEMA = {
  "type"                 => "object",
  "additionalProperties" => false,
  "required"             => [ "result" ],
  "properties"           => {
    "result" => {
      "type"                 => "object",
      "additionalProperties" => false,
      "required"             => [ "rows_inserted", "ids" ],
      "properties"           => {
        "rows_inserted" => { "type" => "integer" },
        "ids"           => { "type" => "array", "items" => { "type" => "integer" } }
      }
    }
  }
}.freeze

INGEST_EMAILS_PARAMS = {
  "operations" => [
    { "type" => "filter_by_ids", "source" => "emails", "ids_from" => "results", "output" => "emails" },
    { "type" => "pick", "keys" => [ "emails" ] }
  ]
}.freeze

QUERY_EMAIL_RECORDS_PARAMS = {
  "table"              => "application_mails",
  "column_name"        => "id",
  "column_values_from" => "stored_ids"
}.freeze

MAP_EMAILS_INPUT_MAPPING = {
  "emails" => { "from" => "ingest_emails", "path" => "emails" }
}.freeze

STORE_EMAILS_INPUT_MAPPING = {
  "emails" => { "from" => "map_emails", "path" => "result.emails" }
}.freeze

STORE_EMAILS_STEP_PARAMS = {
  "label" => "applications",
  "table" => "application_mails"
}.freeze

QUERY_EMAIL_RECORDS_INPUT_MAPPING = {
  "stored_ids" => { "from" => "store_emails", "path" => "result.ids" }
}.freeze

NORMALIZE_EMAILS_STEP_PARAMS = {
  "destination_table"    => "application_mails",
  "columns_to_normalize" => [ "company", "job_title" ]
}.freeze

NORMALIZE_EMAILS_INPUT_MAPPING = {
  "records_to_normalize" => { "from" => "query_email_records", "path" => "application_mails" }
}.freeze

RECONCILE_EMAILS_STEP_PARAMS = {
  "destination_table"  => "interviews",
  "matching_columns"   => [ "company", "job_title" ],
  "statuses"           => [ "pending_reply", "having_interviews", "rejected", "offer_received" ],
  "initial_status"     => "pending_reply"
}.freeze

RECONCILE_EMAILS_INPUT_MAPPING = {
  "emails_to_reconcile" => { "from" => "query_email_records", "path" => "application_mails" }
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
  "Emails::ClassifyAgent" => {
    model:  "mistral-large-latest",
    tools:  [ "Records::TempFileTool" ],
    prompt: <<~PROMPT
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
  "Emails::FilterAgent" => {
    model:         "mistral-large-latest",
    tools:         [ "Records::TempFileTool" ],
    output_schema: FILTER_EMAILS_OUTPUT_SCHEMA,
    prompt:        <<~PROMPT
      You are an email filtering expert. Your job is to identify <emails> from a list related to a <topic>.

      Input:
      {
        "topic": "The topic to filter by (e.g. 'job applications')",
        "emails": [
          {"id": "id of email", "subject": "Email subject line", "tags": ["list", "of", "classification", "tags"] }
        ]
      }

      Steps:
      3. Return ONLY emails tagged with ANY of tags related to the <topic>
        (e.g. for "job applications" topic, tags might include "job", "application", "interview", "offer", etc.).

      Always return a JSON object with a "results" key containing the filtered emails array:
      {"results": [{"id": "id of email", ...}, ...]}

      If no emails are related to the <topic>, return: {"results": []}
    PROMPT
  },
  "Emails::MappingAgent" => {
    model:  "mistral-large-latest",
    tools:  [ "Emails::GetTool", "Records::TempFileTool" ],
    prompt: <<~PROMPT
      Your task is to map raw email data to a structured format for database insertion.

      Input:
      {
        "emails": ["list", "of", "emails", "to", "process"],
      }

      Steps:
      1. For each email in <emails>, call get_email to fetch its full content — this is mandatory before mapping any field.
      2. After reading the full email content, extract and map all required fields.
      3. Base the "action" field strictly on the email body text, not just the subject line.
    PROMPT
  },
  "Records::StoreAgent" => {
    model:         "mistral-large-latest",
    tools:         [ "Emails::GetLabelsTool", "Emails::CreateLabelTool", "Emails::AddLabelsTool",
                    "Records::InsertRowsTool", "Records::ReadSchemaTool", "Emails::GetTool" ],
    output_schema: STORE_EMAILS_OUTPUT_SCHEMA,
    prompt:        <<~PROMPT
      You are a emails processor. For each email you receive:

      Input:
      {
        "label": "The label to add to the email in its provider (e.g. 'applications')",
        "table": "The name of the database table to insert a row into (e.g. 'application_mails')",
        "emails": [ "list", "of", "emails", "to", "process" ]
      }

      Steps:
      1. Check if <label> already exists in the email provider using get_labels tool.
        If not, create it using create_label tool.

      2. Call add_labels to label the email in its provider:
         If add_labels fails, skip labeling but continue processing.

      3. Store a new row in the <table> with the mapped data using insert_rows.
    PROMPT
  },
  "Records::NormalizeAgent" => {
    model:  "gpt-5.1",
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
  },
  "Records::ReconcileAgent" => {
    model:  "gpt-5.1",
    tools:  [ "Records::ReadSchemaTool", "Records::TempFileTool", "Records::SearchSimilarTool",
              "Records::InsertRowsTool", "Records::UpdateRowsTool", "Records::ReadRowsTool" ],
    prompt: <<~PROMPT
      You are a job application lifecycle tracker. Update the <destination_table> records based on <emailsto_reconcile>.
      For each of the given <emailsto_reconcile>.

      Input:
        {
          "statuses": ["list", "of", "allowed", "status", "values"],
          "initial_status"": "The status to set for new records",
          "destination_table": "The name of the database table for normalization.",
          "matching_columns": ["list", "of", "columns", "to", "match"] (e.g. ["company", "job_title"]),
          "emailsto_reconcile": ["list", "of", "columns", "to", "normalize"] (e.g. ["company", "job_title"]),
        }

      Steps:
      2. Read the schema of the <destination_table> to understand its structure.
      3. Read the rows from <destination_table>.
      4. Match <emailsto_reconcile> to existing records in <destination_table> based on the <matching_logic>.
      5. Skip <emailsto_reconcile> that have already been processed.
      6. Set 'unknown' for any blank or missing fields.
      7. For each unique <matching_columns> in the new rows:

          If NOT in <destination_table> → add_rows with:
            status=<initial_status>.

          If ALREADY in <destination_table> → update_rows (match on <matching_columns> via
            column_name: "<matching_columns>", then use data to set fields in schema, and update status based on changes

      Date fallback rule:
        If applied_at is missing or blank for a record, but any other date column is set
        (e.g. rejected_at, first_interview_at, second_interview_at, etc.), set applied_at
        to the earliest non-null date among those columns.
    PROMPT
  },
  "Records::FillAgent" => {
    model:  "gpt-5.1",
    tools:  [ "Records::UpdateRowsTool", "Emails::GetTool" ],
    prompt: <<~PROMPT
      Your task is to fill missing values in the <destination_table> table using the original email content.

      Input:
        {
          "emails": ["list", "of", "emails", "to", "process"],
          "destination_table": "The name of the database table to update.",
        }

      Steps:
      1. For each email in <emails>, always call get_email to fetch its full content — this is mandatory regardless of what fields appear to be populated.
      2. A field is considered missing if its value is null, an empty string, "unknown", "n/a", or any other clear placeholder.
      3. Call update_rows only for records where at least one field was successfully extracted. Skip records where nothing new was found.
    PROMPT
  }
}.freeze

steps = [
  { name: "Fetch Emails",                   kind: :service, agent_class: "Emails::FetchExecutor"                                                                                             },
  { name: "Classify Emails",                kind: :agent,   agent_name: "Emails::ClassifyAgent"                                                                                              },
  { name: "Filter Emails",                  kind: :agent,   agent_name: "Emails::FilterAgent"                                                                                                },
  { name: "Ingest Emails",                  kind: :service, agent_class: "Orchestration::IngestionExecutor",  params: INGEST_EMAILS_PARAMS                                                   },
  { name: "Map Emails",                     kind: :agent,   agent_name: "Emails::MappingAgent",  schema_class: "ApplicationMailsSchema", sa_input_mapping: MAP_EMAILS_INPUT_MAPPING           },
  { name: "Store Emails",                   kind: :agent,   agent_name: "Records::StoreAgent",   sa_params: STORE_EMAILS_STEP_PARAMS,  sa_input_mapping: STORE_EMAILS_INPUT_MAPPING           },
  { name: "Query Email Records",            kind: :service, agent_class: "Orchestration::QueryExecutor",  params: QUERY_EMAIL_RECORDS_PARAMS, sa_input_mapping: QUERY_EMAIL_RECORDS_INPUT_MAPPING },
  { name: "Normalize Emails",               kind: :agent,   agent_name: "Records::NormalizeAgent",  sa_params: NORMALIZE_EMAILS_STEP_PARAMS, sa_input_mapping: NORMALIZE_EMAILS_INPUT_MAPPING },
  { name: "Reconcile Emails to Interviews", kind: :agent,   agent_name: "Records::ReconcileAgent",  sa_params: RECONCILE_EMAILS_STEP_PARAMS, sa_input_mapping: RECONCILE_EMAILS_INPUT_MAPPING },
  { name: "Export to Gist",                 kind: :service, agent_class: "Interviews::GistExportExecutor"                                                                                    }
]

Orchestration::Action.where(name: "Merge Email Records").destroy_all

action_records = steps.map do |attrs|
  agent_record = if attrs[:kind] == :agent
    agent_config = AGENT_DEFINITIONS[attrs[:agent_name]] || {}
    Orchestration::Agent.find_or_initialize_by(name: attrs[:agent_name]).tap do |a|
      a.model         = agent_config[:model]         if agent_config[:model].present?
      a.tools         = agent_config[:tools]         if agent_config[:tools].present?
      a.prompt        = agent_config[:prompt]        if agent_config[:prompt].present?
      a.output_schema = agent_config[:output_schema] if agent_config.key?(:output_schema)
      a.save!
    end
  end

  Orchestration::Action.find_or_initialize_by(name: attrs[:name]).tap do |a|
    a.kind          = attrs[:kind]
    a.agent         = agent_record
    a.agent_class   = attrs[:agent_class]
    a.output_schema = attrs[:output_schema]
    a.params        = attrs[:params]
    a.schema_class  = attrs[:schema_class]
    a.save!
  end
end

APPLICATIONS_WORKFLOW_INITIAL_INPUT_SCHEMA = {
  "type"       => "object",
  "required"   => [ "date", "providers" ],
  "properties" => {
    "date"      => { "type" => "string", "format" => "date" },
    "providers" => {
      "type"     => "array",
      "minItems" => 1,
      "items"    => { "type" => "string", "enum" => [ "gmail", "yahoo" ] }
    }
  }
}.freeze

pipeline = Orchestration::Pipeline.find_or_create_by!(name: "Applications Workflow") do |p|
  p.description          = "Classifies, filters, maps, stores, normalizes and reconciles job-application emails."
  p.enabled              = true
  p.initial_input_schema = APPLICATIONS_WORKFLOW_INITIAL_INPUT_SCHEMA
end

pipeline.update!(initial_input_schema: APPLICATIONS_WORKFLOW_INITIAL_INPUT_SCHEMA)

# Clear and recreate steps to ensure they match the list in db/seeds.rb
# This is needed because the number and order of steps can change.
# Pipeline runs must be cleared first — their action_runs reference step_actions (FK).
pipeline.pipeline_runs.destroy_all
pipeline.steps.destroy_all

steps.each_with_index do |step_attrs, index|
  action = action_records[index]
  step = pipeline.steps.create!(
    name:     action.name,
    position: index + 1
  )

  Orchestration::StepAction.create!(
    step:          step,
    action:        action,
    position:      1,
    output_key:    action.name.parameterize(separator: "_"),
    params:        step_attrs[:sa_params],
    input_mapping: step_attrs[:sa_input_mapping]
  )
end

# Create agents that exist in app/agents/ but are not part of any pipeline step.
%w[Records::FillAgent].each do |name|
  config = AGENT_DEFINITIONS.fetch(name)
  Orchestration::Agent.find_or_initialize_by(name: name).tap do |a|
    a.model  = config[:model]  if config[:model].present?
    a.tools  = config[:tools]  if config[:tools].present?
    a.prompt = config[:prompt] if config[:prompt].present?
    a.save!
  end
end

# == Evaluation Datasets per Agent ==

puts "Seeding Leva::Dataset from ActionRun history per agent..."

AGENT_DEFINITIONS.each_key do |agent_name|
  result = Evaluation::DatasetSeeder.call(agent_name: agent_name, sample_size: 20)
  puts "Dataset '#{result.agent_name}': #{result.created} created, #{result.skipped} skipped."
end
