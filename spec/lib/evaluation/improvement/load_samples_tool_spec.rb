
require "rails_helper"

RSpec.describe Evaluation::Improvement::LoadSamplesTool do
  subject(:tool) { described_class.new }

  let(:experiment) { create(:evaluation_experiment) }

  describe "#execute" do
    it "returns an empty array when the experiment has no samples" do
      expect(tool.execute(experiment_id: experiment.id)).to eq([])
    end

    context "with a dataset sample and output" do
      let(:dataset_sample) do
        create(:evaluation_dataset_sample, dataset: experiment.dataset, input: { "email" => "test" })
      end

      before do
        create(:evaluation_sample,
               experiment: experiment,
               dataset_sample: dataset_sample,
               tool_calls: [],
               output: "test output")
      end

      it "returns input/output pairs for samples" do
        result = tool.execute(experiment_id: experiment.id)
        expect(result).to be_an(Array)
        expect(result.first).to include(input: { "email" => "test" }, output: "test output")
      end
    end

    it "returns empty output string when output is nil" do
      dataset_sample = create(:evaluation_dataset_sample, dataset: experiment.dataset, input: { "x" => 1 })
      create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample, output: nil)

      result = tool.execute(experiment_id: experiment.id)
      expect(result.first[:output]).to eq("")
    end

    it "respects the number_of_samples limit" do
      3.times do
        ds = create(:evaluation_dataset_sample, dataset: experiment.dataset, input: { "n" => rand })
        create(:evaluation_sample, experiment: experiment, dataset_sample: ds, output: "x")
      end

      result = tool.execute(experiment_id: experiment.id, number_of_samples: 2)
      expect(result.size).to be <= 2
    end
  end
end
