module Records
  class ReadSchemaTool < RubyLLM::Tool
    include ModelResolver

    def self.readonly? = true

    description "Return the column names for a database table."

    parameter :table, type: :string,
                  description: "Table name: application_mails or interviews",
                  required: true

    def name = "read_schema"

    def execute(table:)
      model = resolve_model(table)
      { headers: model.tool_column_names }
    rescue ModelNotFound => e
      { error: e.message }
    end
  end
end
