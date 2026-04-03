# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# == Applications Workflow Pipeline ==
#
# Mirrors Pipeline::ApplicationsWorkflow steps 1-8, plus two IngestionExecutor steps for fan-in joins.

STORE_EMAILS_OUTPUT_SCHEMA = {
  "type" => "object",
  "required" => [ "result" ],
  "properties" => {
    "result" => {
      "type" => "object",
      "properties" => {
        "rows_inserted" => { "type" => "integer" },
        "ids"           => { "type" => "array" }
      }
    }
  }
}.freeze

INGEST_EMAILS_PARAMS = {
  "operations" => [
    { "type" => "filter_by_ids", "source" => "emails", "ids_from" => "result.results", "output" => "emails" },
    { "type" => "pick", "keys" => [ "emails" ] }
  ]
}.freeze

QUERY_EMAIL_RECORDS_PARAMS = {
  "table"              => "application_mails",
  "column_name"        => "id",
  "column_values_from" => "stored_ids"
}.freeze

QUERY_EMAIL_RECORDS_INPUT_MAPPING = {
  "stored_ids" => { "from_step" => "Store Emails", "path" => "result.ids" }
}.freeze

NORMALIZE_EMAILS_INPUT_MAPPING = {
  "records_to_normalize" => { "from_step" => "Query Email Records", "path" => "application_mails" },
  "destination_table"    => { "value" => "application_mails" },
  "columns_to_normalize" => { "value" => [ "company", "job_title" ] }
}.freeze

RECONCILE_EMAILS_INPUT_MAPPING = {
  "emails_to_reconcile" => { "from_step" => "Query Email Records", "path" => "application_mails" },
  "destination_table"   => { "value" => "interviews" },
  "matching_columns"    => { "value" => [ "company", "job_title" ] },
  "statuses"            => { "value" => [ "pending_reply", "having_interviews", "rejected", "offer_received" ] },
  "initial_status"      => { "value" => "pending_reply" }
}.freeze

steps = [
  { name: "Fetch Emails",                   agent_class: "Emails::FetchExecutor"                                                                              },
  { name: "Classify Emails",                agent_class: "Emails::ClassifyAgent"                                                                              },
  { name: "Filter Emails",                  agent_class: "Emails::FilterAgent"                                                                                },
  { name: "Ingest Emails",                  agent_class: "Orchestration::IngestionExecutor", params: INGEST_EMAILS_PARAMS                                     },
  { name: "Map Emails",                     agent_class: "Emails::MappingAgent",             schema_class: "ApplicationMailsSchema"                            },
  { name: "Store Emails",                   agent_class: "Records::StoreAgent",              output_schema: STORE_EMAILS_OUTPUT_SCHEMA                         },
  { name: "Query Email Records",            agent_class: "Orchestration::QueryExecutor",    params: QUERY_EMAIL_RECORDS_PARAMS,   input_mapping: QUERY_EMAIL_RECORDS_INPUT_MAPPING  },
  { name: "Normalize Emails",               agent_class: "Records::NormalizeAgent",                                              input_mapping: NORMALIZE_EMAILS_INPUT_MAPPING     },
  { name: "Reconcile Emails to Interviews", agent_class: "Records::ReconcileAgent", input_mapping: RECONCILE_EMAILS_INPUT_MAPPING                           },
  { name: "Export to Gist",                 agent_class: "Interviews::GistExportExecutor"                                                                     }
]

Orchestration::Action.where(name: "Merge Email Records").destroy_all

action_records = steps.map do |attrs|
  Orchestration::Action.find_or_initialize_by(name: attrs[:name]).tap do |a|
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
    name:          action.name,
    position:      index + 1,
    input_mapping: step_attrs[:input_mapping]
  )

  Orchestration::StepAction.create!(
    step:     step,
    action:   action,
    position: 1
  )
end
