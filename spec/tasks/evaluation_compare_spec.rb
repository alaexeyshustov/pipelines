require "rails_helper"
require "rake"

RSpec.describe "evaluation:compare rake task" do # rubocop:disable RSpec/DescribeClass
  let(:task_name) { "evaluation:compare" }
  let(:baseline)  { create(:leva_experiment, name: "baseline-exp") }
  let(:candidate) { create(:leva_experiment, name: "candidate-exp") }

  def make_eval_result(experiment:, score:, metric_name:)
    runner_result = create(:leva_runner_result, experiment: experiment)
    eval_result = create(:leva_evaluation_result,
      experiment: experiment,
      runner_result: runner_result,
      dataset_record: runner_result.dataset_record,
      score: score)
    create(:evaluation_justification, evaluation_result: eval_result, metric_name: metric_name)
  end


  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task[task_name].reenable
  end

  context "when both IDs are provided and experiments exist" do
    before do
      make_eval_result(experiment: baseline,  score: 3.0, metric_name: "accuracy")
      make_eval_result(experiment: candidate, score: 4.0, metric_name: "accuracy")
    end

    it "prints experiment names" do
      expect { Rake::Task[task_name].invoke(baseline.id, candidate.id) }
        .to output(/##{baseline.id}.*baseline-exp/).to_stdout
      Rake::Task[task_name].reenable
      expect { Rake::Task[task_name].invoke(baseline.id, candidate.id) }
        .to output(/##{candidate.id}.*candidate-exp/).to_stdout
    end

    it "prints a positive delta for an improved metric" do
      expect { Rake::Task[task_name].invoke(baseline.id, candidate.id) }
        .to output(/accuracy.*\+1\.00/).to_stdout
    end

    it "prints overall scores and delta" do
      expect { Rake::Task[task_name].invoke(baseline.id, candidate.id) }
        .to output(/OVERALL.*3\.00.*4\.00.*\+1\.00/).to_stdout
    end
  end

  context "when baseline ID is missing" do
    it "raises ArgumentError with usage message" do
      expect { Rake::Task[task_name].invoke(nil, candidate.id) }
        .to raise_error(ArgumentError, /Usage/)
    end
  end

  context "when candidate ID is missing" do
    it "raises ArgumentError with usage message" do
      expect { Rake::Task[task_name].invoke(baseline.id, nil) }
        .to raise_error(ArgumentError, /Usage/)
    end
  end

  context "when a metric exists only in baseline" do
    before do
      make_eval_result(experiment: baseline, score: 3.0, metric_name: "only_baseline")
    end

    it "prints n/a for the candidate column and delta" do
      expect { Rake::Task[task_name].invoke(baseline.id, candidate.id) }
        .to output(/only_baseline.*n\/a.*n\/a/).to_stdout
    end
  end
end
