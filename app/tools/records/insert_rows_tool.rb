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

      results = collect_results(parsed_data[:records], model)
      { status: "rows_added" }.merge(results).merge(rows_added: results[:ids].size)
    rescue ModelNotFound => error
      { status: "insert_failed", error: error.message }
    end

    private

    def collect_results(records, model)
      # steep:ignore:start
      results = { ids: [], duplicate: [], invalids: [] } # Ruby::UnannotatedEmptyCollection
      # steep:ignore:end
      records.each do |row|
        attrs = row.is_a?(Hash) ? row.transform_keys(&:to_s).slice(*model::COLUMN_NAMES) : {} # : Hash[String, untyped]
        next if attrs.empty?
        result = insert_record(model, attrs)
        result.keys.each { |key| results[key] << result[key] }
      end
      results
    end

    def insert_record(model, attrs)
      record = model.create!(attrs)
      { ids: record.id }
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      dup_id = find_duplicate_id(model, attrs)
      return { duplicate: { existing_id: dup_id } } if dup_id

      error.is_a?(ActiveRecord::RecordInvalid) ? { invalids: error.message } : { invalids: "Unique constraint violated" }
    end

    def find_duplicate_id(model, attrs)
      model.validators
           .select { |v| v.is_a?(ActiveRecord::Validations::UniquenessValidator) }
           .each do |validator|
             record = find_by_validator(validator, attrs, model)
             return record.id if record
           end
      nil
    end

    def find_by_validator(validator, attrs, model)
      scope_opt = validator.options[:scope] # : Array[String] | String | Symbol
      key_cols  = (validator.attributes.map(&:to_s) + Array(scope_opt).map(&:to_s))
      key_attrs = key_cols.index_with { |col| attrs[col] }.compact
      return nil if key_attrs.size < key_cols.size

      model.find_by(key_attrs)
    end

    def safe_parse_data(data)
      records = JSON.parse(data)
      raise ArgumentError, "data must be a JSON array of objects" unless records.is_a?(Array)

      { status: "success", records: records }
    rescue JSON::ParserError => error
      { status: "invalid_data", error: "Failed to parse JSON data: #{error.message}" }
    end
  end
end
