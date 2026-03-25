require "json"

module Records
  class UpdateRowsTool < RubyLLM::Tool
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

      attrs = attrs.transform_keys(&:to_s).slice(*model::COLUMN_NAMES)
      record.update(attrs) unless attrs.empty?
      { status: "row_updated" }
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn "Skipping row for #{model}: #{e.message}"
      { status: "update_failed", error: e.message }
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn "Row not found for #{model}: #{e.message}"
      { status: "update_failed", error: e.message }
    end

    private

    def resolve_model(table)
      case table.to_s
      when "application_mails" then ApplicationMail
      when "interviews"        then Interview
      else raise ArgumentError, "Unknown table '#{table}'. Use: application_mails, interviews."
      end
    end
  end
end
