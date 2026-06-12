require "json"

module Records
  class InsertRowsTool < RubyLLM::Tool
    include ModelResolver

    def self.readonly? = false

    description "Insert rows into a database table. Duplicate or invalid rows are skipped."

    param :table, type: :string, desc: "Table name: application_mails or interviews", required: true
    param :data,  type: :string, desc: "JSON-encoded array of row objects to insert", required: true

    def name = "insert_rows"

    def execute(table:, data:)
      model = resolve_model(table)
      records = parse_records(data)
      ids = Array.new
      duplicate = Array.new
      invalids = Array.new

      records.each do |row|
        attrs = row.transform_keys(&:to_s).slice(*model.tool_column_names)
        next if attrs.empty?

        result = insert_record(model, attrs)
        ids << result[:id] if result.key?(:id)
        duplicate << result[:duplicate] if result.key?(:duplicate)
        invalids << result[:invalid] if result.key?(:invalid)
      end

      { status: "rows_added", ids: ids, duplicate: duplicate, invalids: invalids, rows_added: ids.size }
    rescue JSON::ParserError => error
      { status: "invalid_data", error: "Failed to parse JSON data: #{error.message}" }
    rescue ModelNotFound => error
      { status: "insert_failed", error: error.message }
    end

    private

    def insert_record(model, attrs)
      record = model.create!(attrs)
      { id: record.id }
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      dup_id = find_duplicate_id(model, attrs)
      return { duplicate: { existing_id: dup_id } } unless dup_id.nil?

      error.is_a?(ActiveRecord::RecordInvalid) ? { invalid: error.message } : { invalid: "Unique constraint violated" }
    end

    def find_duplicate_id(model, attrs)
      validators = model.validators.filter_map do |validator|
        validator if validator.is_a?(ActiveRecord::Validations::UniquenessValidator)
      end # Array[ActiveRecord::Validations::UniquenessValidator]
      validators.each do |validator|
        record = find_by_validator(validator, attrs, model)
        return record.id unless record.nil?
      end
      nil
    end

    def find_by_validator(validator, attrs, model)
      return nil unless validator.attributes.is_a?(Array)

      key_cols  = extract_key_columns(validator)
      key_attrs = build_key_attrs(key_cols, attrs)
      return nil if key_attrs.nil?

      model.find_by(key_attrs)
    end

    def extract_scope_columns(scope_opt)
      case scope_opt
      when Array  then scope_opt.filter_map { |v| v.to_s if v.is_a?(String) || v.is_a?(Symbol) }
      when String, Symbol then [ scope_opt.to_s ]
      else Array.new
      end
    end

    def extract_key_columns(validator)
      scope_cols = extract_scope_columns(validator.options[:scope])
      validator.attributes.filter_map { |attr| attr.to_s if attr.is_a?(String) || attr.is_a?(Symbol) } + scope_cols
    end

    def build_key_attrs(key_cols, attrs)
      collector = Hash.new # : Hash[String, json_object_value]
      key_attrs = key_cols.each_with_object(collector) do |column, memo|
        value = attrs[column]
        memo[column] = value unless value.nil?
      end
      key_attrs if key_attrs.size >= key_cols.size
    end

    def parse_records(data)
      records = JSON.parse(data) #: Array[json_object]
      raise ArgumentError, "data must be a JSON array of objects" unless records.is_a?(Array)
      raise ArgumentError, "data must be a JSON array of objects" unless records.all? { |record| record.is_a?(Hash) }

      records
    end
  end
end
