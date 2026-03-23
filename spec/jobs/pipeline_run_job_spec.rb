require 'rails_helper'

RSpec.describe PipelineRunJob, type: :job do
  let(:pipeline) { create(:orchestration_pipeline) }
  let(:step1) { create(:orchestration_step, pipeline: pipeline, name: "extract", position: 1) }
  let(:step2) { create(:orchestration_step, pipeline: pipeline, name: "transform", position: 2) }
  let(:action) { create(:orchestration_action, agent_class: "EmailClassifyAgent") }
  let(:step_action1) { create(:orchestration_step_action, step: step1, action: action, position: 1) }
  let(:pipeline_run) { create(:orchestration_pipeline_run, pipeline: pipeline, status: "pending") }

  let(:stub_agent) { instance_double(EmailClassifyAgent) }

  before do
    allow(EmailClassifyAgent).to receive(:new).and_return(stub_agent)
    allow(stub_agent).to receive(:ask).and_return("classification result")
  end

  describe '#perform' do
    context 'happy path — single step with one action' do
      before { step_action1 }

      it 'transitions PipelineRun from pending to running to completed' do
        expect { PipelineRunJob.perform_later(pipeline_run.id) }
          .to change { pipeline_run.reload.status }.from("pending").to("completed")
      end

      it 'sets started_at and finished_at on the PipelineRun' do
        PipelineRunJob.perform_later(pipeline_run.id)
        pipeline_run.reload
        expect(pipeline_run.started_at).not_to be_nil
        expect(pipeline_run.finished_at).not_to be_nil
      end

      it 'creates an ActionRun record for the step action' do
        expect { PipelineRunJob.perform_later(pipeline_run.id) }
          .to change(Orchestration::ActionRun, :count).by(1)
      end

      it 'marks the ActionRun as completed with output' do
        PipelineRunJob.perform_later(pipeline_run.id)
        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("completed")
        expect(action_run.output).to eq({ "result" => "classification result" })
      end

      it 'passes the resolved input to the ActionRun' do
        PipelineRunJob.perform_later(pipeline_run.id)
        action_run = Orchestration::ActionRun.last
        expect(action_run.input).to eq({})
      end
    end

    context 'fail-fast — action raises an error' do
      before do
        step_action1
        allow(stub_agent).to receive(:ask).and_raise(RuntimeError, "agent exploded")
      end

      it 'marks PipelineRun as failed' do
        PipelineRunJob.perform_later(pipeline_run.id)
        expect(pipeline_run.reload.status).to eq("failed")
      end

      it 'records the error message on PipelineRun' do
        PipelineRunJob.perform_later(pipeline_run.id)
        expect(pipeline_run.reload.error).to eq("agent exploded")
      end

      it 'marks the ActionRun as failed' do
        PipelineRunJob.perform_later(pipeline_run.id)
        action_run = Orchestration::ActionRun.last
        expect(action_run.status).to eq("failed")
        expect(action_run.error).to eq("agent exploded")
      end

      it 'sets finished_at on PipelineRun' do
        PipelineRunJob.perform_later(pipeline_run.id)
        expect(pipeline_run.reload.finished_at).not_to be_nil
      end
    end

    context 'two steps with input_mapping on second step' do
      let(:action2) { create(:orchestration_action, agent_class: "EmailClassifyAgent") }
      let(:step_action2) { create(:orchestration_step_action, step: step2, action: action2, position: 1) }

      before do
        step_action1
        step_action2
        allow(EmailClassifyAgent).to receive(:new).and_return(stub_agent)
        allow(stub_agent).to receive(:ask).and_return("step output")
        step2.update!(input_mapping: {
          "processed" => { "from_step" => "extract", "path" => "result", "merge" => "concat" }
        })
      end

      it 'passes step1 output as resolved input to step2 ActionRun' do
        PipelineRunJob.perform_later(pipeline_run.id)
        step2_action_run = Orchestration::ActionRun.joins(:step_action)
          .where(step_actions: { step_id: step2.id }).first
        expect(step2_action_run.input).to eq({ "processed" => "step output" })
      end

      it 'completes both steps and the PipelineRun' do
        PipelineRunJob.perform_later(pipeline_run.id)
        expect(pipeline_run.reload.status).to eq("completed")
        expect(Orchestration::ActionRun.where(status: "completed").count).to eq(2)
      end
    end
  end
end
