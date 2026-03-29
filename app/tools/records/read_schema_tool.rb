module Records
  class ReadSchemaTool < RubyLLM::Tool
    include ModelResolver

    description "Return the column names for a database table."

    param :table, type: :string,
                  desc: "Table name: application_mails or interviews",
                  required: true

    def name = "read_schema"

    def execute(table:)
      model = resolve_model(table)
      { headers: model::COLUMN_NAMES }
    rescue ModelNotFound => e
      { error: e.message }
    end
  end
end
