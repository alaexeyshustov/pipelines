
class MoveStoreEmailsOutputSchemaToAgent < ActiveRecord::Migration[8.1]
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
    Orchestration::Agent.find_by(name: "Records::StoreAgent")
      &.update!(output_schema: SCHEMA)

    Orchestration::Action.find_by(name: "Store Emails")
      &.update!(output_schema: nil)
  end

  def down
  end
end
