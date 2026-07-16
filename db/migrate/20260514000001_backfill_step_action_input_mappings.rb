
# Backfills input_mapping (and params where needed) for the Applications Workflow
# step_actions that were created before explicit input_mapping was required.
#
# After the PipelineRunner rewrite (PR #82), data only flows between steps via
# explicit input_mapping — nil means the step receives {}. The seeds define the
# correct values; this migration applies them to existing installations.
class BackfillStepActionInputMappings < ActiveRecord::Migration[8.1]
  STEP_CONFIGS = {
    "Fetch Emails" => {
      input_mapping: {
        "date"      => { "from" => "_initial", "path" => "date",      "optional" => true },
        "providers" => { "from" => "_initial", "path" => "providers", "optional" => true }
      }
    },
    "Classify Emails" => {
      input_mapping: {
        "emails" => { "from" => "fetch_emails", "path" => "emails" }
      }
    },
    "Filter Emails" => {
      input_mapping: {
        "emails" => { "from" => "classify_emails", "path" => "results" }
      },
      params: {
        "topic" => "job applications"
      }
    },
    "Ingest Emails" => {
      input_mapping: {
        "emails"  => { "from" => "fetch_emails",  "path" => "emails" },
        "results" => { "from" => "filter_emails", "path" => "results" }
      }
    }
  }.freeze

  def up
    STEP_CONFIGS.each do |step_name, config|
      step_action_ids = select_values(<<~SQL.squish)
        SELECT sa.id
        FROM step_actions sa
        JOIN steps ON steps.id = sa.step_id
        WHERE steps.name = #{quote(step_name)}
          AND sa.input_mapping IS NULL
      SQL

      next if step_action_ids.empty?

      parts = [ "input_mapping = #{quote(config[:input_mapping].to_json)}" ]
      parts << "params = #{quote(config[:params].to_json)}" if config[:params] && needs_params_backfill?(step_name)

      execute <<~SQL.squish
        UPDATE step_actions
        SET #{parts.join(', ')}
        WHERE id IN (#{step_action_ids.join(', ')})
      SQL
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def needs_params_backfill?(step_name)
    result = select_values(<<~SQL.squish)
      SELECT sa.id
      FROM step_actions sa
      JOIN steps ON steps.id = sa.step_id
      WHERE steps.name = #{quote(step_name)}
        AND sa.params IS NULL
    SQL
    result.any?
  end

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
