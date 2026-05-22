# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::DatasetSample do
  describe "validations" do
    it "is valid with required attributes" do
      sample = build(:evaluation_dataset_sample)
      expect(sample).to be_valid
    end

    it "requires dataset" do
      sample = build(:evaluation_dataset_sample, dataset: nil)
      expect(sample).not_to be_valid
      expect(sample.errors[:dataset]).to be_present
    end

    it "requires input" do
      sample = build(:evaluation_dataset_sample, input: nil)
      expect(sample).not_to be_valid
      expect(sample.errors[:input]).to be_present
    end

    it "allows nil expected_tool_calls" do
      sample = build(:evaluation_dataset_sample, expected_tool_calls: nil)
      expect(sample).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a dataset" do
      sample = create(:evaluation_dataset_sample)
      expect(sample.dataset).to be_a(Evaluation::Dataset)
    end

    it "has many samples" do
      dataset_sample = create(:evaluation_dataset_sample)
      experiment = create(:evaluation_experiment, dataset: dataset_sample.dataset)
      prompt = create(:orchestration_prompt)
      create(:evaluation_sample, dataset_sample: dataset_sample, experiment: experiment, prompt: prompt)
      expect(dataset_sample.samples.count).to eq(1)
    end
  end
end
