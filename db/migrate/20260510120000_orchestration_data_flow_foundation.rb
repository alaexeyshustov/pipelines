
# Foundation slice for the orchestration data-flow refactor (PRD #77, issue #78).
#
# Moves `input_mapping` from `steps` to `step_actions`, introduces a stable
# `output_key` handle on every `step_action`, and adds an optional
# `input_schema` column to `actions`. Backfills existing rows so the new shape
# carries the same semantics as the old `steps.input_mapping`.
#
# The new columns are intentionally unused at runtime in this slice; later
# slices wire them into the resolver, validator, and runner.
class OrchestrationDataFlowFoundation < ActiveRecord::Migration[8.1]
  OUTPUT_KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

  def up
    add_column :step_actions, :input_mapping, :json
    add_column :step_actions, :output_key, :string
    add_column :actions, :input_schema, :json

    backfill_output_keys
    backfill_step_action_mappings

    change_column_null :step_actions, :output_key, false
    add_index :step_actions, [ :step_id, :output_key ], unique: true,
              name: "index_step_actions_on_step_id_and_output_key"

    remove_column :steps, :input_mapping
  end

  def down
    add_column :steps, :input_mapping, :json

    remove_index :step_actions, name: "index_step_actions_on_step_id_and_output_key"
    remove_column :step_actions, :output_key
    remove_column :step_actions, :input_mapping
    remove_column :actions, :input_schema
  end

  private

  def backfill_output_keys
    say_with_time "backfilling step_actions.output_key from action.name" do
      rows = execute(<<~SQL.squish).then(&:to_a)
        SELECT step_actions.id        AS id,
               step_actions.step_id   AS step_id,
               actions.name           AS action_name
        FROM step_actions
        JOIN actions ON actions.id = step_actions.action_id
        ORDER BY step_actions.step_id, step_actions.position
      SQL

      # Track assigned keys per step in memory to avoid O(n²) uniqueness SELECTs.
      assigned_per_step = Hash.new { |h, k| h[k] = Set.new }

      rows.each do |row|
        step_id = row["step_id"]
        key = derive_output_key(row["action_name"], assigned_per_step[step_id])
        assigned_per_step[step_id] << key
        execute "UPDATE step_actions SET output_key = #{quote(key)} WHERE id = #{row['id'].to_i}"
      end
    end
  end

  # Within a single `step`, two parallel `step_actions` referencing the same
  # `Action` would parameterize to the same key. Append a suffix when needed
  # so the unique index can be added.
  def derive_output_key(action_name, existing_keys)
    base = action_name.to_s.parameterize(separator: "_")
    base = "action" if base.blank?
    base = "x_#{base}" unless base.match?(/\A[a-z]/)

    candidate = base
    suffix    = 2
    while existing_keys.include?(candidate)
      candidate = "#{base}_#{suffix}"
      suffix += 1
    end
    candidate
  end

  def backfill_step_action_mappings
    say_with_time "splitting steps.input_mapping into step_actions.input_mapping/params" do
      step_rows = select_all(<<~SQL.squish).to_a
        SELECT id, input_mapping
        FROM steps
        WHERE input_mapping IS NOT NULL AND input_mapping <> ''
      SQL

      step_rows.each { |row| backfill_one_step(row) }
    end
  end

  def backfill_one_step(step_row)
    step_id  = step_row["id"]
    raw      = step_row["input_mapping"]
    mapping  = parse_json_mapping(raw)
    return if mapping.empty?

    step_action_rows = select_all(<<~SQL.squish).to_a
      SELECT step_actions.id, step_actions.params, step_actions.input_mapping
      FROM step_actions
      WHERE step_actions.step_id = #{step_id.to_i}
    SQL

    step_action_rows.each do |sa_row|
      apply_mapping_to_step_action(sa_row, mapping)
    end
  end

  def apply_mapping_to_step_action(sa_row, mapping)
    existing_params  = parse_json_mapping(sa_row["params"])
    new_params       = existing_params.dup
    new_input_map    = {}

    mapping.each do |key, spec|
      next unless spec.is_a?(Hash)

      if spec.key?("value")
        new_params[key] = spec["value"]
      elsif spec.key?("from_step")
        translated = translate_from_step_spec(spec)
        new_input_map[key] = translated if translated
      end
    end

    update_sql = +"UPDATE step_actions SET "
    parts = []
    parts << "params = #{quote(new_params.to_json)}" if new_params != existing_params
    parts << "input_mapping = #{quote(new_input_map.to_json)}" unless new_input_map.empty?
    return if parts.empty?

    update_sql << parts.join(", ")
    update_sql << " WHERE id = #{sa_row['id'].to_i}"
    execute update_sql
  end

  # Translates the legacy `{ "from_step" => name, "path" => "...", "merge" => ... }`
  # shape into the new `{ "from" => output_key, "path" => "..." }` shape.
  # `from_step` -> the upstream step's first step_action's output_key.
  # The legacy `merge` strategy is dropped (resolver rewrite owns merging next).
  def translate_from_step_spec(spec)
    upstream_name = spec["from_step"]
    return nil if upstream_name.blank?

    upstream_key = upstream_output_key_for(upstream_name)
    return nil if upstream_key.blank?

    translated = { "from" => upstream_key }
    translated["path"] = spec["path"] if spec["path"].present?
    translated
  end

  def upstream_output_key_for(step_name)
    return "_initial" if step_name == "initial"

    sql = <<~SQL.squish
      SELECT step_actions.output_key
      FROM step_actions
      JOIN steps ON steps.id = step_actions.step_id
      WHERE steps.name = #{quote(step_name)}
      ORDER BY step_actions.position ASC
      LIMIT 1
    SQL
    row = select_all(sql).first
    row && row["output_key"]
  end

  def parse_json_mapping(raw)
    return {} if raw.nil? || raw == ""
    return raw if raw.is_a?(Hash)

    parsed = JSON.parse(raw)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end

  def select_all(sql)
    ActiveRecord::Base.connection.select_all(sql)
  end
end
