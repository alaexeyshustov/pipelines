require "json"

module Records
  class UpdateRowsTool < RubyLLM::Tool
    include ModelResolver

    def self.readonly? = false

    description "Update rows in a database table. Duplicate or invalid rows are skipped."

    param :table, type: :string, desc: "Table name: application_mails or interviews", required: true
    param :id,    type: :string, desc: "Row ID", required: true
    param :data,  type: :string, desc: "JSON-encoded object of row attributes to update", required: true

    def name = "update_rows"

    def execute(table:, id:, data:)
      model  = resolve_model(table)
      record = model.find(id.to_i)
      apply_update(record, model, data)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique,
           ActiveRecord::RecordNotFound, ModelNotFound => e
      Rails.logger.warn "Update failed for #{table}: #{e.message}"
      { status: "update_failed", error: e.message }
    end

    private

    def apply_update(record, model, data)
      attrs = JSON.parse(data) #: json_object_value
      raise ArgumentError, "data must be a JSON object" unless attrs.is_a?(Hash)
      return { status: "invalid_attributes" } if attrs.empty?

      attrs = attrs.transform_keys(&:to_s).slice(*model.tool_column_names)
      record.update(attrs) unless attrs.empty?
      { status: "row_updated" }
    end
  end
end
