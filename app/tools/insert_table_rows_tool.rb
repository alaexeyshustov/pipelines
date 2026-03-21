# frozen_string_literal: true

require "json"

class InsertTableRowsTool < RubyLLM::Tool
  description "Insert rows into a database table. Duplicate or invalid rows are skipped."

  param :table, type: :string, desc: "Table name: application_mails or interviews", required: true
  param :data,  type: :string, desc: "JSON-encoded array of row objects to insert", required: true

  def execute(table:, data:)
    model   = resolve_model(table)
    records = JSON.parse(data)
    raise ArgumentError, "data must be a JSON array" unless records.is_a?(Array)

    inserted = 0
    records.each do |row|
      attrs = row.is_a?(Hash) ? row.transform_keys(&:to_s).slice(*model::COLUMN_NAMES) : {}
      next if attrs.empty?

      model.create!(attrs)
      inserted += 1
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn "Skipping row for #{model}: #{e.message}"
    end

    { status: "rows_added", rows_added: inserted, total_rows: model.count }
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
