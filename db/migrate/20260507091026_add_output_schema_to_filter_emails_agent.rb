
class AddOutputSchemaToFilterEmailsAgent < ActiveRecord::Migration[8.1]
  # Without output_schema the runtime agent builder never calls with_schema(),
  # so Mistral is unconstrained and occasionally returns a bare array instead of
  # {"results":[...]}. IngestionExecutor's filter_by_ids then digs "result.results"
  # on an Array node, gets nil, and filters every email out (Run #72).
  SCHEMA = {
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

  def up
    Orchestration::Agent.find_by(name: "Emails::FilterAgent")
      &.update!(output_schema: SCHEMA)
  end

  def down
  end
end
