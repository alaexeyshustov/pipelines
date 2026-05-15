# frozen_string_literal: true

# ClassifyAgent now runs with structured output so Mistral reliably returns all
# email IDs as strings (including Yahoo integer UIDs, which were silently lost
# in pipeline run #92). Adding output_schema has two consequences:
#
#   1. The runner skips the {"result" => ...} wrapper, so classify_emails output
#      shape changes from {"result"=>{"results"=>[...]}} to {"results"=>[...]}.
#   2. Filter Emails steps that still hold the old "result.results" path would
#      break — this migration unconditionally repoints them to "results".
class AddOutputSchemaToClassifyEmailsAgent < ActiveRecord::Migration[8.1]
  CLASSIFY_SCHEMA = {
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

  FILTER_EMAILS_INPUT_MAPPING = {
    "emails" => { "from" => "classify_emails", "path" => "results" }
  }.freeze

  OLD_FILTER_EMAILS_INPUT_MAPPING = {
    "emails" => { "from" => "classify_emails", "path" => "result.results" }
  }.freeze

  def up
    Orchestration::Agent.find_by(name: "Emails::ClassifyAgent")
      &.update!(output_schema: CLASSIFY_SCHEMA)

    fix_filter_emails_path
  end

  def down
    Orchestration::Agent.find_by(name: "Emails::ClassifyAgent")
      &.update!(output_schema: nil)

    restore_filter_emails_path
  end

  private

  def fix_filter_emails_path
    step_action_ids = select_values(<<~SQL.squish)
      SELECT sa.id
      FROM step_actions sa
      JOIN steps ON steps.id = sa.step_id
      WHERE steps.name = 'Filter Emails'
        AND sa.input_mapping IS NOT NULL
    SQL

    return if step_action_ids.empty?

    execute <<~SQL.squish
      UPDATE step_actions
      SET input_mapping = #{quote(FILTER_EMAILS_INPUT_MAPPING.to_json)}
      WHERE id IN (#{step_action_ids.join(', ')})
    SQL
  end

  def restore_filter_emails_path
    step_action_ids = select_values(<<~SQL.squish)
      SELECT sa.id
      FROM step_actions sa
      JOIN steps ON steps.id = sa.step_id
      WHERE steps.name = 'Filter Emails'
        AND sa.input_mapping = #{quote(FILTER_EMAILS_INPUT_MAPPING.to_json)}
    SQL

    return if step_action_ids.empty?

    execute <<~SQL.squish
      UPDATE step_actions
      SET input_mapping = #{quote(OLD_FILTER_EMAILS_INPUT_MAPPING.to_json)}
      WHERE id IN (#{step_action_ids.join(', ')})
    SQL
  end

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
