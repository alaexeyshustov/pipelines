# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Improvement::LoadSamplesTool do
  subject(:tool) { described_class.new }

  let(:experiment) { create(:evaluation_experiment) }

  describe "#execute" do
    it "returns an empty array when the experiment has no runner results" do
      expect(tool.execute(experiment_id: experiment.id)).to eq([])
    end

    it "returns input/output pairs for runner results with valid JSON predictions" do
      dataset_record = create(:evaluation_dataset_record, dataset: experiment.dataset)
      recordable = dataset_record.recordable
      allow(recordable).to receive(:input).and_return("test input") if recordable.respond_to?(:input)

      create(:evaluation_runner_result,
             experiment: experiment,
             dataset_record: dataset_record,
             prediction: { "output" => "test output", "tool_calls" => [] }.to_json)

      result = tool.execute(experiment_id: experiment.id)
      expect(result).to be_an(Array)
      expect(result.first).to include(:output)
    end

    it "skips runner results with invalid JSON predictions" do
      dataset_record = create(:evaluation_dataset_record, dataset: experiment.dataset)
      create(:evaluation_runner_result,
             experiment: experiment,
             dataset_record: dataset_record,
             prediction: "not valid json")

      expect(tool.execute(experiment_id: experiment.id)).to eq([])
    end

    it "respects the number_of_samples limit" do
      3.times do
        dr = create(:evaluation_dataset_record, dataset: experiment.dataset)
        create(:evaluation_runner_result,
               experiment: experiment,
               dataset_record: dr,
               prediction: { "output" => "x", "tool_calls" => [] }.to_json)
      end

      result = tool.execute(experiment_id: experiment.id, number_of_samples: 2)
      expect(result.size).to be <= 2
    end
  end
end
