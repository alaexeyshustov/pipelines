require "json"

module Records
  class InsertRowsTool < RubyLLM::Tool
    include ModelResolver

    description "Insert rows into a database table. Duplicate or invalid rows are skipped."

    param :table, type: :string, desc: "Table name: application_mails or interviews", required: true
    param :data,  type: :string, desc: "JSON-encoded array of row objects to insert", required: true

    def name = "insert_rows"

    def execute(table:, data:)
      model       = resolve_model(table)
      parsed_data = safe_parse_data(data)
      return parsed_data if parsed_data[:status] != "success"

      records   = parsed_data[:records]
      results = { ids: [], duplicate: [], invalids: [] }

      records.each do |row|
        attrs = row.is_a?(Hash) ? row.transform_keys(&:to_s).slice(*model::COLUMN_NAMES) : {}
        next if attrs.empty?
        result = insert_record(model, attrs)
        result.keys.each { |k| results[k] << result[k] }
      end

      { status: "rows_added" }.merge(results).merge(rows_added: results[:ids].size)
    rescue ModelNotFound => e
      { status: "insert_failed", error: e.message }
    end

    private

    def insert_record(model, attrs)
      record = model.create!(attrs)
      { ids: record.id }
    rescue ActiveRecord::RecordInvalid => e
      if (dup_id = find_duplicate_id(model, attrs))
        { duplicate: { existing_id: dup_id } }
      else
        { invalids: e.message }
      end
    rescue ActiveRecord::RecordNotUnique
      { duplicate: { existing_id: find_duplicate_id(model, attrs) } }
    end

    def find_duplicate_id(model, attrs)
      model.validators.each do |v|
        next unless v.is_a?(ActiveRecord::Validations::UniquenessValidator)

        key_cols = (v.attributes.map(&:to_s) + Array(v.options[:scope]).map(&:to_s))
        key_attrs = key_cols.index_with { |k| attrs[k] }.compact
        next if key_attrs.size < key_cols.size

        record = model.find_by(key_attrs)
        return record.id if record
      end
      nil
    end

    def safe_parse_data(data)
      records = JSON.parse(data)
      raise ArgumentError, "data must be a JSON array of objects" unless records.is_a?(Array)

      { status: "success", records: records }
    rescue JSON::ParserError => e
      { status: "invalid_data", error: "Failed to parse JSON data: #{e.message}" }
    end
  end
end
