require "json"

module Tools
  # Database CRUD tool replacing the CSV-based manage_csv from the MCP server.
  # Supports reading and writing ApplicationMail and Interview records via ActiveRecord.
  class ManageDatabaseTool < RubyLLM::Tool
    description "Read and write job application tracking data in the SQLite database. " \
                "Supports actions: 'read' (query records), 'add_rows' (insert records), " \
                "'update_rows' (update records matching a column value)."

    param :action,       type: :string, desc: "Action: read, add_rows, update_rows", required: true
    param :table,        type: :string, desc: "Table name: application_mails or interviews", required: true
    param :data,         type: :string, desc: "JSON-encoded rows to insert or update (for add_rows/update_rows)", required: false
    param :column_name,  type: :string, desc: "Column name to filter/match on (for update_rows or filtering read)", required: false
    param :column_value, type: :string, desc: "Column value to match (for update_rows or filtering read)", required: false

    def execute(action:, table:, data: nil, column_name: nil, column_value: nil)
      model = resolve_model(table)
      case action
      when "read"        then read(model, column_name, column_value)
      when "add_rows"    then add_rows(model, data)
      when "update_rows" then update_rows(model, data, column_name, column_value)
      else
        raise ArgumentError, "Unknown action '#{action}'. Use: read, add_rows, update_rows."
      end
    end

    private

    def resolve_model(table)
      case table.to_s
      when "application_mails" then ApplicationMail
      when "interviews"        then Interview
      else raise ArgumentError, "Unknown table '#{table}'. Use: application_mails, interviews."
      end
    end

    # ── read ───────────────────────────────────────────────────────────────────

    def read(model, column_name, column_value)
      scope = model.all
      scope = scope.where(column_name => column_value) if column_name && column_value
      rows  = model.as_rows(scope)
      { headers: model::COLUMN_NAMES, rows: rows, row_count: rows.size }
    end

    # ── add_rows ───────────────────────────────────────────────────────────────

    def add_rows(model, data)
      raise ArgumentError, "data is required for add_rows" if data.nil? || data.strip.empty?

      records = JSON.parse(data)
      raise ArgumentError, "data must be a JSON array" unless records.is_a?(Array)

      inserted = 0
      records.each do |row|
        attrs = row.is_a?(Hash) ? row.transform_keys(&:to_s) : {}
        # Filter to only known columns to avoid attribute errors
        attrs = attrs.slice(*permitted_columns(model))
        next if attrs.empty?

        model.create!(attrs)
        inserted += 1
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        Rails.logger.warn "Skipping duplicate row for #{model}: #{e.message}"
      end

      { status: "rows_added", rows_added: inserted, total_rows: model.count }
    end

    # ── update_rows ────────────────────────────────────────────────────────────

    def update_rows(model, data, column_name, column_value)
      raise ArgumentError, "data is required for update_rows" if data.nil? || data.strip.empty?
      raise ArgumentError, "column_name and column_value are required for update_rows" if column_name.nil? || column_value.nil?

      updates  = JSON.parse(data)
      raise ArgumentError, "data must be a JSON object of column → value" unless updates.is_a?(Hash)

      # Filter update keys to permitted columns
      filtered = updates.transform_keys(&:to_s).slice(*permitted_columns(model))
      scope    = model.where(column_name => column_value)
      count    = scope.update_all(filtered)

      { status: "rows_updated", rows_updated: count, total_rows: model.count }
    end

    def permitted_columns(model)
      model::COLUMN_NAMES
    end
  end
end
