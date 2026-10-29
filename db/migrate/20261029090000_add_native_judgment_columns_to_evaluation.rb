# GH #194: native RubyLLM::Judge grading. Metrics gain a question type, levels and a pass threshold;
# results keep the native answer (`raw`) next to the normalized 0.0..1.0 `score`.
class AddNativeJudgmentColumnsToEvaluation < ActiveRecord::Migration[8.1]
  def change
    change_table :evaluation_metrics, bulk: true do |t|
      t.string :kind, null: false, default: "probability"
      t.json :levels
      t.float :minimum
    end

    change_table :evaluation_evaluation_results, bulk: true do |t|
      t.json :raw
      t.float :confidence
      t.boolean :passed # rubocop:disable Rails/ThreeStateBooleanColumn -- nil = no threshold / unknown
    end
  end
end
