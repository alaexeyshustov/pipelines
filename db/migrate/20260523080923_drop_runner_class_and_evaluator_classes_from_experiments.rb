class DropRunnerClassAndEvaluatorClassesFromExperiments < ActiveRecord::Migration[8.1]
  def change
    remove_column :evaluation_experiments, :runner_class, :string
    remove_column :evaluation_experiments, :evaluator_classes, :text
  end
end
