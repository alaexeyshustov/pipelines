require "json"

module Records
  class UpdateRowsTool < RubyLLM::Tool
    include ModelResolver

    description "Update rows in a database table. Duplicate or invalid rows are skipped."

    param :table, type: :string, desc: "Table name: application_mails or interviews", required: true
    param :id,    type: :string, desc: "Row ID", required: true
    param :data,  type: :string, desc: "JSON-encoded object of row attributes to update", required: true

    def name = "update_rows"

    def execute(table:, id:, data:)
      model  = resolve_model(table)
      record = model.find(id)

      attrs = JSON.parse(data)
      raise ArgumentError, "data must be a JSON object" unless attrs.is_a?(Hash)
      return { status: "invalid_attributes" } if attrs.empty?

      attrs = attrs.transform_keys(&:to_s).slice(*model::COLUMN_NAMES)
      record.update(attrs) unless attrs.empty?
      { status: "row_updated" }
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn "Skipping row for #{model}: #{e.message}"
      { status: "update_failed", error: e.message }
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn "Row not found for #{model}: #{e.message}"
      { status: "update_failed", error: e.message }
    rescue ModelNotFound => e
      { status: "update_failed", error: e.message }
    end
  end
end
