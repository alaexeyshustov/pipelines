# GH #301: the live prompt version is chosen explicitly via evaluation_prompts.active instead of "newest wins" or a
# JSON flag in metadata. activated_at records "was active before" (set on every activation, never cleared).
# Plain SQL on purpose: no app models, so the migration keeps working as the models change.
class AddActiveToEvaluationPrompts < ActiveRecord::Migration[8.1]
  def up
    add_column :evaluation_prompts, :active, :boolean, null: false, default: false
    add_column :evaluation_prompts, :activated_at, :datetime

    # One-time backfill: the newest version per agent is what the resolver served until now, so keep it live.
    execute <<~SQL.squish
      UPDATE evaluation_prompts SET active = 1, activated_at = CURRENT_TIMESTAMP
      WHERE id IN (
        SELECT id FROM (
          SELECT id, ROW_NUMBER() OVER (PARTITION BY name ORDER BY version DESC, id DESC) AS rank
          FROM evaluation_prompts
        ) WHERE rank = 1
      )
    SQL

    execute "UPDATE evaluation_prompts SET metadata = json_remove(metadata, '$.active') WHERE json_valid(metadata)"

    add_index :evaluation_prompts, :name, unique: true, where: "active", name: "index_evaluation_prompts_on_name_where_active"
  end

  def down
    remove_index :evaluation_prompts, name: "index_evaluation_prompts_on_name_where_active"
    remove_column :evaluation_prompts, :activated_at
    remove_column :evaluation_prompts, :active
  end
end
