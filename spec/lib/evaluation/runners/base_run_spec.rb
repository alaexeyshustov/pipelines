# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Runners::BaseRun do
  subject(:base_run) { described_class.new }

  describe "#execute" do
    it "raises NotImplementedError" do
      expect { base_run.execute(nil) }
        .to raise_error(NotImplementedError, /execute/)
    end
  end

  describe "#execute_and_store" do
    let(:experiment) { create(:evaluation_experiment) }
    let(:dataset_record) { create(:evaluation_dataset_record, dataset: experiment.dataset) }

    let(:concrete_run) do
      stub_const("TestConcreteRun", Class.new(described_class) do
        def execute(_recordable) = '{"output":"ok"}'
      end)
      TestConcreteRun.new
    end

    it "creates a RunnerResult record" do
      expect { concrete_run.execute_and_store(experiment, dataset_record, experiment.prompt) }
        .to change(Evaluation::RunnerResult, :count).by(1)
    end

    it "stores the prediction returned by execute" do
      concrete_run.execute_and_store(experiment, dataset_record, experiment.prompt)
      expect(Evaluation::RunnerResult.last.prediction).to eq('{"output":"ok"}')
    end

    it "links the result to the experiment" do
      concrete_run.execute_and_store(experiment, dataset_record, experiment.prompt)
      expect(Evaluation::RunnerResult.last.experiment).to eq(experiment)
    end
  end
end
