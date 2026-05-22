# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Evaluators::BaseEval do
  subject(:base_eval) { described_class.new }

  describe "#evaluate" do
    it "raises NotImplementedError" do
      expect { base_eval.evaluate(nil, nil) }
        .to raise_error(NotImplementedError, /evaluate/)
    end
  end

  describe "#evaluate_and_store" do
    let(:dataset) { create(:evaluation_dataset) }
    let(:experiment) do
      create(:evaluation_experiment, dataset: dataset,
             runner_class: "Evaluation::Runners::StubbedAgentRun",
             evaluator_classes: [ "Evaluation::Evaluators::LLMJudgeEval" ])
    end
    let(:dataset_sample) { create(:evaluation_dataset_sample, dataset: dataset) }
    let(:sample) { create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample) }

    let(:concrete_eval) do
      stub_const("TestConcreteEval", Class.new(described_class) do
        def evaluate(_sample, _dataset_sample) = 3.5
      end)
      TestConcreteEval.new
    end

    it "creates an EvaluationResult record" do
      expect { concrete_eval.evaluate_and_store(experiment, sample) }
        .to change(Evaluation::EvaluationResult, :count).by(1)
    end

    it "stores the score returned by evaluate" do
      concrete_eval.evaluate_and_store(experiment, sample)
      expect(Evaluation::EvaluationResult.last.score).to eq(3.5)
    end

    it "links the result to the experiment" do
      concrete_eval.evaluate_and_store(experiment, sample)
      expect(Evaluation::EvaluationResult.last.experiment).to eq(experiment)
    end
  end
end
