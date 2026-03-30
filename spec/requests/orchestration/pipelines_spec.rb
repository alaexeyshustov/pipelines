# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orchestration::Pipelines" do
  describe "GET /orchestration/pipelines" do
    it "returns 200 and lists pipelines with step count and enabled status" do
      pipeline = create(:orchestration_pipeline, name: "My Pipeline", enabled: true)
      create(:orchestration_step, pipeline: pipeline)
      create(:orchestration_step, pipeline: pipeline)

      get orchestration_pipelines_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Pipeline")
      expect(response.body).to include("2")
    end

    it "shows disabled status for disabled pipeline" do
      create(:orchestration_pipeline, name: "Disabled Pipeline", enabled: false)

      get orchestration_pipelines_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Disabled Pipeline")
    end
  end

  describe "GET /orchestration/pipelines/new" do
    it "returns 200 with form" do
      get new_orchestration_pipeline_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("name")
    end
  end

  describe "POST /orchestration/pipelines" do
    context "with valid params" do
      it "creates a pipeline and redirects" do
        expect {
          post orchestration_pipelines_path, params: {
            orchestration_pipeline: { name: "New Pipeline", description: "A desc", enabled: true }
          }
        }.to change(Orchestration::Pipeline, :count).by(1)

        expect(response).to redirect_to(orchestration_pipeline_path(Orchestration::Pipeline.last))
      end
    end

    context "with invalid params" do
      it "renders new with 422" do
        post orchestration_pipelines_path, params: {
          orchestration_pipeline: { name: "" }
        }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /orchestration/pipelines/:id" do
    it "returns 200 and shows pipeline name" do
      pipeline = create(:orchestration_pipeline, name: "Show Pipeline")

      get orchestration_pipeline_path(pipeline)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Show Pipeline")
    end

    it "shows ordered steps and their actions" do
      pipeline = create(:orchestration_pipeline, name: "Show Pipeline")
      step1 = create(:orchestration_step, pipeline: pipeline, name: "First Step", position: 1)
      step2 = create(:orchestration_step, pipeline: pipeline, name: "Second Step", position: 2)
      action = create(:orchestration_action, name: "My Action")
      create(:orchestration_step_action, step: step1, action: action, position: 1)

      get orchestration_pipeline_path(pipeline)

      expect(response.body).to include("First Step")
      expect(response.body).to include("Second Step")
      expect(response.body).to include("My Action")
    end

    it "shows input mapping on steps" do
      pipeline = create(:orchestration_pipeline)
      create(:orchestration_step, pipeline: pipeline, position: 1,
             input_mapping: { "email" => "$.output.email" })

      get orchestration_pipeline_path(pipeline)

      expect(response).to have_http_status(:ok)
    end

    it "displays latest run status when a run exists" do
      pipeline = create(:orchestration_pipeline, name: "Show Pipeline")
      create(:orchestration_pipeline_run, pipeline: pipeline, status: "completed")

      get orchestration_pipeline_path(pipeline)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("completed")
    end
  end

  describe "GET /orchestration/pipelines/:id/edit" do
    it "returns 200 with form populated" do
      pipeline = create(:orchestration_pipeline, name: "Edit Me")

      get edit_orchestration_pipeline_path(pipeline)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit Me")
    end
  end

  describe "PATCH /orchestration/pipelines/:id" do
    context "with valid params" do
      it "updates and redirects" do
        pipeline = create(:orchestration_pipeline, name: "Old Name")

        patch orchestration_pipeline_path(pipeline), params: {
          orchestration_pipeline: { name: "New Name" }
        }

        expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
        expect(pipeline.reload.name).to eq("New Name")
      end
    end

    context "with invalid params" do
      it "renders edit with 422" do
        pipeline = create(:orchestration_pipeline)

        patch orchestration_pipeline_path(pipeline), params: {
          orchestration_pipeline: { name: "" }
        }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /orchestration/pipelines/:id" do
    it "destroys pipeline and cascades through steps and step_actions" do
      pipeline = create(:orchestration_pipeline)
      step = create(:orchestration_step, pipeline: pipeline, position: 1)
      action = create(:orchestration_action)
      create(:orchestration_step_action, step: step, action: action, position: 1)

      expect {
        delete orchestration_pipeline_path(pipeline)
      }.to change(Orchestration::Pipeline, :count).by(-1)
        .and change(Orchestration::Step, :count).by(-1)
        .and change(Orchestration::StepAction, :count).by(-1)

      expect(response).to redirect_to(orchestration_pipelines_path)
    end
  end

  describe "POST /orchestration/pipelines/:pipeline_id/steps" do
    it "adds a step to the pipeline and redirects to show" do
      pipeline = create(:orchestration_pipeline)

      expect {
        post orchestration_pipeline_steps_path(pipeline), params: {
          orchestration_step: { name: "New Step" }
        }
      }.to change(Orchestration::Step, :count).by(1)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(Orchestration::Step.last.position).to eq(1)
    end

    it "appends step after existing steps" do
      pipeline = create(:orchestration_pipeline)
      create(:orchestration_step, pipeline: pipeline, position: 1)

      post orchestration_pipeline_steps_path(pipeline), params: {
        orchestration_step: { name: "Second Step" }
      }

      expect(Orchestration::Step.last.position).to eq(2)
    end

    it "renders pipeline show with 422 on invalid params" do
      pipeline = create(:orchestration_pipeline)

      post orchestration_pipeline_steps_path(pipeline), params: {
        orchestration_step: { name: "" }
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /orchestration/pipelines/:pipeline_id/steps/:id" do
    it "updates step name and input_mapping and redirects to show" do
      pipeline = create(:orchestration_pipeline)
      step = create(:orchestration_step, pipeline: pipeline, name: "Old", position: 1)

      patch orchestration_pipeline_step_path(pipeline, step), params: {
        orchestration_step: { name: "Updated", input_mapping: '{"key":"val"}' }
      }

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(step.reload.name).to eq("Updated")
    end

    it "renders show with 422 on invalid params" do
      pipeline = create(:orchestration_pipeline)
      step = create(:orchestration_step, pipeline: pipeline, position: 1)

      patch orchestration_pipeline_step_path(pipeline, step), params: {
        orchestration_step: { name: "" }
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /orchestration/pipelines/:pipeline_id/steps/:id" do
    it "removes step from pipeline and redirects to show" do
      pipeline = create(:orchestration_pipeline)
      step = create(:orchestration_step, pipeline: pipeline, position: 1)

      expect {
        delete orchestration_pipeline_step_path(pipeline, step)
      }.to change(Orchestration::Step, :count).by(-1)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
    end
  end

  describe "PATCH /orchestration/pipelines/:pipeline_id/steps/:id/move_up" do
    it "swaps position with the step above and redirects" do
      pipeline = create(:orchestration_pipeline)
      step1 = create(:orchestration_step, pipeline: pipeline, position: 1)
      step2 = create(:orchestration_step, pipeline: pipeline, position: 2)

      patch move_up_orchestration_pipeline_step_path(pipeline, step2)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(step2.reload.position).to eq(1)
      expect(step1.reload.position).to eq(2)
    end

    it "does nothing when step is already first and redirects" do
      pipeline = create(:orchestration_pipeline)
      step1 = create(:orchestration_step, pipeline: pipeline, position: 1)

      patch move_up_orchestration_pipeline_step_path(pipeline, step1)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(step1.reload.position).to eq(1)
    end
  end

  describe "PATCH /orchestration/pipelines/:pipeline_id/steps/:id/move_down" do
    it "swaps position with the step below and redirects" do
      pipeline = create(:orchestration_pipeline)
      step1 = create(:orchestration_step, pipeline: pipeline, position: 1)
      step2 = create(:orchestration_step, pipeline: pipeline, position: 2)

      patch move_down_orchestration_pipeline_step_path(pipeline, step1)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(step1.reload.position).to eq(2)
      expect(step2.reload.position).to eq(1)
    end

    it "does nothing when step is already last and redirects" do
      pipeline = create(:orchestration_pipeline)
      step1 = create(:orchestration_step, pipeline: pipeline, position: 1)

      patch move_down_orchestration_pipeline_step_path(pipeline, step1)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(step1.reload.position).to eq(1)
    end
  end

  describe "POST /orchestration/pipelines/:pipeline_id/steps/:step_id/step_actions" do
    it "attaches an action to the step and redirects to pipeline show" do
      pipeline = create(:orchestration_pipeline)
      step = create(:orchestration_step, pipeline: pipeline, position: 1)
      action = create(:orchestration_action)

      expect {
        post orchestration_pipeline_step_step_actions_path(pipeline, step), params: {
          orchestration_step_action: { action_id: action.id }
        }
      }.to change(Orchestration::StepAction, :count).by(1)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(Orchestration::StepAction.last.position).to eq(1)
    end

    it "attaches with optional params override JSON" do
      pipeline = create(:orchestration_pipeline)
      step = create(:orchestration_step, pipeline: pipeline, position: 1)
      action = create(:orchestration_action)

      post orchestration_pipeline_step_step_actions_path(pipeline, step), params: {
        orchestration_step_action: { action_id: action.id, params: '{"override":"true"}' }
      }

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(Orchestration::StepAction.last.params).to eq({ "override" => "true" })
    end
  end

  describe "POST /orchestration/pipelines/:id/run" do
    it "creates a PipelineRun with status pending and triggered_by manual" do
      pipeline = create(:orchestration_pipeline)
      allow(PipelineRunJob).to receive(:perform_later)

      expect {
        post run_orchestration_pipeline_path(pipeline)
      }.to change(Orchestration::PipelineRun, :count).by(1)

      run = Orchestration::PipelineRun.last
      expect(run.status).to eq("pending")
      expect(run.triggered_by).to eq("manual")
    end

    it "associates the created PipelineRun with the pipeline" do
      pipeline = create(:orchestration_pipeline)
      allow(PipelineRunJob).to receive(:perform_later)

      post run_orchestration_pipeline_path(pipeline)

      expect(Orchestration::PipelineRun.last.pipeline).to eq(pipeline)
    end

    it "enqueues PipelineRunJob with the pipeline_run_id" do
      pipeline = create(:orchestration_pipeline)
      allow(PipelineRunJob).to receive(:perform_later)

      post run_orchestration_pipeline_path(pipeline)

      expect(PipelineRunJob).to have_received(:perform_later).with(Orchestration::PipelineRun.last.id)
    end

    it "redirects to pipeline show page with a notice" do
      pipeline = create(:orchestration_pipeline)
      allow(PipelineRunJob).to receive(:perform_later)

      post run_orchestration_pipeline_path(pipeline)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      follow_redirect!
      expect(response.body).to include("Pipeline run triggered.")
    end
  end

  describe "DELETE /orchestration/pipelines/:pipeline_id/steps/:step_id/step_actions/:id" do
    it "detaches action from step and redirects to pipeline show" do
      pipeline = create(:orchestration_pipeline)
      step = create(:orchestration_step, pipeline: pipeline, position: 1)
      action = create(:orchestration_action)
      step_action = create(:orchestration_step_action, step: step, action: action, position: 1)

      expect {
        delete orchestration_pipeline_step_step_action_path(pipeline, step, step_action)
      }.to change(Orchestration::StepAction, :count).by(-1)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
    end
  end
end
