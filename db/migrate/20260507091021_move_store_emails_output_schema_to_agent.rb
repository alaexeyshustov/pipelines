class MoveStoreEmailsOutputSchemaToAgent < ActiveRecord::Migration[8.1]
  # Migration-local models: the app models track the current schema, not this migration's.
  class MigrationAgent < ActiveRecord::Base
    self.table_name = "orchestration_agents"
    self.inheritance_column = nil
  end

  class MigrationAction < ActiveRecord::Base
    self.table_name = "actions"
    self.inheritance_column = nil
  end

  # output_schema was on the Action, not the Agent record.
  # run_agent checks action.agent.output_schema to decide wrapping and to call with_schema.
  # With schema only on the action, the LLM received no structured-output guidance and
  # the runner always wrapped output — causing "output.result must be an object" (Run #66)
  # when the LLM returned a non-Hash.
  #
  # Moving schema to the Agent record:
  #   - enables with_schema → reliable structured output from the LLM
  #   - skips the { "result" => ... } wrapper (output is already correctly shaped)
  #   - downstream "result.ids" path continues to work unchanged
  SCHEMA = {
    "type"       => "object",
    "required"   => [ "result" ],
    "properties" => {
      "result" => {
        "type"       => "object",
        "properties" => {
          "rows_inserted" => { "type" => "integer" },
          "ids"           => { "type" => "array" }
        }
      }
    }
  }.freeze

  def up
    MigrationAgent.find_by(name: "Records::StoreAgent")
      &.update_columns(output_schema: SCHEMA)

    MigrationAction.find_by(name: "Store Emails")
      &.update_columns(output_schema: nil)
  end

  def down
  end
end
