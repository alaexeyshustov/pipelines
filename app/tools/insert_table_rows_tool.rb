# frozen_string_literal: true

require "json"

class InsertTableRowsTool < RubyLLM::Tool
  description "Insert rows into a database table. Duplicate or invalid rows are skipped."

  param :table, type: :string, desc: "Table name: application_mails or interviews", required: true
  param :data,  type: :string, desc: "JSON-encoded array of row objects to insert", required: true

  def execute(table:, data:)
    model   = resolve_model(table)
    parsed_data = safe_parse_data(data)
    return parsed_data if parsed_data[:status] != "success"

    records = parsed_data[:records]
    inserted = 0
    ids = []
    records.each do |row|
      attrs = row.is_a?(Hash) ? row.transform_keys(&:to_s).slice(*model::COLUMN_NAMES) : {}
      next if attrs.empty?

      record = model.create!(attrs)
      ids << record.id
      inserted += 1
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn "Skipping row for #{model}: #{e.message}"
    end

    { status: "rows_added", rows_added: inserted, total_rows: model.count, ids: ids }
  end

  private

  def safe_parse_data(data)
    records = JSON.parse(data)

    return { status: "invalid_data", error: "Expected an array of objects" } unless records.is_a?(Array)

    { status: "success", records: records }
  rescue JSON::ParserError => e
    { status: "invalid_data", error: "Failed to parse JSON data: #{e.message}" }
  end

  def resolve_model(table)
    case table.to_s
    when "application_mails" then ApplicationMail
    when "interviews"        then Interview
    else raise ArgumentError, "Unknown table '#{table}'. Use: application_mails, interviews."
    end
  end
end
