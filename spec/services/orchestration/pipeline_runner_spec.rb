require 'rails_helper'

RSpec.describe Orchestration::PipelineRunner do
  let(:pipeline)     { create(:orchestration_pipeline) }
  let(:step1)        { create(:orchestration_step, pipeline: pipeline, name: "extract", position: 1) }
  let(:action)       { create(:orchestration_action, agent_class: "Emails::ClassifyAgent") }
  let(:pipeline_run) { create(:orchestration_pipeline_run, pipeline: pipeline, status: "pending") }
  let(:stub_agent)   { instance_double(Emails::ClassifyAgent) }

  before do
    allow(Emails::ClassifyAgent).to receive(:new).and_return(stub_agent)
    allow(stub_agent).to receive(:ask).and_return("classification result")
  end

  describe '#call' do
    context 'with a single step and one action' do
      before { create(:orchestration_step_action, step: step1, action: action, position: 1) }

      it 'transitions PipelineRun from pending to completed' do
        expect { described_class.new(pipeline_run).call }
          .to change { pipeline_run.reload.status }.from("pending").to("completed")
      end

      it 'creates an ActionRun for the step action' do
        expect { described_class.new(pipeline_run).call }
          .to change(Orchestration::ActionRun, :count).by(1)
      end

      it 'marks the ActionRun completed with output from the agent' do
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("completed")
        expect(action_run.output).to eq({ "result" => "classification result" })
      end
    end

    context 'when an action raises' do
      before do
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        allow(stub_agent).to receive(:ask).and_raise(RuntimeError, "agent exploded")
      end

      it 'marks the PipelineRun as failed with the error message' do
        described_class.new(pipeline_run).call
        pipeline_run.reload
        expect(pipeline_run.status).to eq("failed")
        expect(pipeline_run.error).to eq("agent exploded")
        expect(pipeline_run.finished_at).not_to be_nil
      end

      it 'marks the ActionRun as failed with the error message' do
        described_class.new(pipeline_run).call
        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("failed")
        expect(action_run.error).to eq("agent exploded")
      end
    end

    context 'with two steps and input_mapping on the second step' do
      before do
        step2 = create(:orchestration_step, pipeline: pipeline, name: "transform", position: 2)
        action2 = create(:orchestration_action, agent_class: "Emails::ClassifyAgent")
        create(:orchestration_step_action, step: step1, action: action, position: 1)
        create(:orchestration_step_action, step: step2, action: action2, position: 1)
        allow(stub_agent).to receive(:ask).and_return("step output")
        step2.update!(input_mapping: {
          "processed" => { "from_step" => "extract", "path" => "result", "merge" => "concat" }
        })
      end

      it 'passes step1 output as resolved input to the step2 ActionRun' do
        described_class.new(pipeline_run).call
        step2_action_run = Orchestration::ActionRun
          .joins(step_action: :step)
          .where(steps: { name: "transform" }).first
        expect(step2_action_run.input).to eq({ "processed" => "step output" })
      end

      it 'completes both steps and the PipelineRun' do
        described_class.new(pipeline_run).call
        expect(pipeline_run.reload.status).to eq("completed")
        expect(Orchestration::ActionRun.where(status: "completed").count).to eq(2)
      end
    end
  end
end
