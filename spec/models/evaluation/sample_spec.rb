# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Sample do
  describe "validations" do
    it "is valid with required attributes" do
      sample = build(:evaluation_sample)
      expect(sample).to be_valid
    end

    it "requires dataset_sample" do
      sample = build(:evaluation_sample, dataset_sample: nil)
      expect(sample).not_to be_valid
      expect(sample.errors[:dataset_sample]).to be_present
    end

    it "requires prompt" do
      sample = build(:evaluation_sample, prompt: nil)
      expect(sample).not_to be_valid
      expect(sample.errors[:prompt]).to be_present
    end

    it "allows nil experiment" do
      sample = build(:evaluation_sample, experiment: nil)
      expect(sample).to be_valid
    end
  end

  describe "associations" do
    it "belongs to an experiment" do
      sample = create(:evaluation_sample)
      expect(sample.experiment).to be_a(Evaluation::Experiment)
    end

    it "belongs to a dataset_sample" do
      sample = create(:evaluation_sample)
      expect(sample.dataset_sample).to be_a(Evaluation::DatasetSample)
    end

    it "belongs to a prompt" do
      sample = create(:evaluation_sample)
      expect(sample.prompt).to be_a(Evaluation::Prompt)
    end
  end
end
