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
    let(:dataset_sample) { create(:evaluation_dataset_sample, dataset: experiment.dataset) }

    let(:concrete_run) do
      stub_const("TestConcreteRun", Class.new(described_class) do
        def execute(_dataset_sample) = '{"tool_calls":[],"output":"ok"}'
      end)
      TestConcreteRun.new
    end

    it "creates a Sample record" do
      expect { concrete_run.execute_and_store(experiment, dataset_sample, experiment.prompt) }
        .to change(Evaluation::Sample, :count).by(1)
    end

    it "stores the output returned by execute" do
      concrete_run.execute_and_store(experiment, dataset_sample, experiment.prompt)
      expect(Evaluation::Sample.last.output).to eq("ok")
    end

    it "stores empty tool_calls returned by execute" do
      concrete_run.execute_and_store(experiment, dataset_sample, experiment.prompt)
      expect(Evaluation::Sample.last.tool_calls).to eq([])
    end

    it "links the result to the experiment" do
      concrete_run.execute_and_store(experiment, dataset_sample, experiment.prompt)
      expect(Evaluation::Sample.last.experiment).to eq(experiment)
    end
  end
end
