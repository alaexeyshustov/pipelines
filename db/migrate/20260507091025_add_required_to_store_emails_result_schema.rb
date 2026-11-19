class AddRequiredToStoreEmailsResultSchema < ActiveRecord::Migration[8.1]
  # Mistral requires every object with "properties" to also declare a "required"
  # array listing all keys. The "result" object was missing this, causing:
  #   "In context=('properties', 'result'), 'required' is required to be
  #    supplied and to be an array including every key in properties.
  #    Missing 'rows_inserted'." (Run #71)
  SCHEMA = {
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

  def up
    execute <<~SQL.squish
      UPDATE orchestration_agents SET output_schema = #{quote(SCHEMA.to_json)} WHERE name = 'Records::StoreAgent'
    SQL
  end

  def down
  end
end
