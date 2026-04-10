# frozen_string_literal: true

require "rails_helper"

# Integration test covering the full pipeline lifecycle:
# 1. Setup – create actions, pipeline, steps, and step_action attachments via HTTP
# 2. Run – execute PipelineRunner with a service-object step (QueryExecutor, no HTTP)
#              and an agentic step (ClassifyAgent, Mistral API stubbed via VCR cassette)
# 3. Edit    – update pipeline metadata, reorder/add/remove steps, swap action attachments
RSpec.describe "Orchestration::Pipeline lifecycle" do
  describe "setup: creating a pipeline with steps and actions via HTTP" do
    # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
    it "creates a pipeline with a service-object action and an agentic action end-to-end" do
      # --- actions ---

      expect {
        post orchestration_actions_path, params: {
          orchestration_action: {
            name: "Query Interviews",
            agent_class: "Orchestration::QueryExecutor",
            description: "Fetches interviews from the database",
            params: '{"table":"interviews","column_name":"status","column_values":["screening"],"columns":["id","company","job_title"]}'
          }
        }
      }.to change(Orchestration::Action, :count).by(1)

      query_action = Orchestration::Action.last
      expect(response).to redirect_to(orchestration_actions_path)
      expect(query_action.agent_class).to eq("Orchestration::QueryExecutor")
      expect(query_action.params).to include("table" => "interviews")

      expect {
        post orchestration_actions_path, params: {
          orchestration_action: {
            name: "Classify Emails",
            agent_class: "Emails::ClassifyAgent",
            description: "Classifies emails using Mistral AI"
          }
        }
      }.to change(Orchestration::Action, :count).by(1)

      classify_action = Orchestration::Action.last
      expect(response).to redirect_to(orchestration_actions_path)
      expect(classify_action.agent_class).to eq("Emails::ClassifyAgent")

      # --- pipeline ---

      expect {
        post orchestration_pipelines_path, params: {
          orchestration_pipeline: { name: "Job Application Pipeline", enabled: true }
        }
      }.to change(Orchestration::Pipeline, :count).by(1)

      pipeline = Orchestration::Pipeline.last
      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(pipeline.name).to eq("Job Application Pipeline")
      expect(pipeline.enabled).to be true

      # --- steps ---

      post orchestration_pipeline_steps_path(pipeline), params: {
        orchestration_step: { name: "Fetch Interviews" }
      }
      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      fetch_step = Orchestration::Step.find_by!(name: "Fetch Interviews")
      expect(fetch_step.position).to eq(1)

      post orchestration_pipeline_steps_path(pipeline), params: {
        orchestration_step: { name: "Classify Emails" }
      }
      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      classify_step = Orchestration::Step.find_by!(name: "Classify Emails")
      expect(classify_step.position).to eq(2)

      # --- attach actions to steps ---

      expect {
        post orchestration_pipeline_step_step_actions_path(pipeline, fetch_step), params: {
          orchestration_step_action: { action_id: query_action.id }
        }
      }.to change(Orchestration::StepAction, :count).by(1)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(Orchestration::StepAction.last.action).to eq(query_action)

      expect {
        post orchestration_pipeline_step_step_actions_path(pipeline, classify_step), params: {
          orchestration_step_action: { action_id: classify_action.id }
        }
      }.to change(Orchestration::StepAction, :count).by(1)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(Orchestration::StepAction.last.action).to eq(classify_action)

      # --- verify show page reflects full structure ---

      get orchestration_pipeline_path(pipeline)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Job Application Pipeline")
      expect(response.body).to include("Fetch Interviews")
      expect(response.body).to include("Classify Emails")
      expect(response.body).to include("Query Interviews")
    end
    # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
  end

  describe "run: executing a pipeline with service-object and agentic steps" do
    let!(:query_action) do
      create(:orchestration_action,
        name: "Query Interviews",
        agent_class: "Orchestration::QueryExecutor",
        params: { "table" => "interviews", "column_name" => "status", "column_values" => [ "screening" ] })
    end
    let!(:classify_action) do
      create(:orchestration_action, name: "Classify Emails", agent_class: "Emails::ClassifyAgent")
    end
    let!(:pipeline) { create(:orchestration_pipeline, name: "Job Application Pipeline", enabled: true) }
    let!(:fetch_step) { create(:orchestration_step, pipeline: pipeline, name: "Fetch Interviews", position: 1) }
    let!(:classify_step) { create(:orchestration_step, pipeline: pipeline, name: "Classify Emails", position: 2) }

    before do
      create(:orchestration_step_action, step: fetch_step, action: query_action, position: 1)
      create(:orchestration_step_action, step: classify_step, action: classify_action, position: 1)
    end

    # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
    it "completes both steps and records action run outputs",
       vcr: { cassette_name: "orchestration/pipeline_lifecycle/classify_agent_run" } do
      pipeline_run = Orchestration::PipelineRun.create!(
        pipeline: pipeline,
        status: "pending",
        triggered_by: "manual"
      )

      Orchestration::PipelineRunner.new(pipeline_run).call

      pipeline_run.reload
      expect(pipeline_run.status).to eq("completed")
      expect(pipeline_run.action_runs.count).to eq(2)

      query_run = pipeline_run.action_runs
        .joins(:step_action)
        .find_by(step_actions: { action_id: query_action.id })

      expect(query_run.status).to eq("completed")
      expect(query_run.output).to have_key("interviews")
      expect(query_run.output["interviews"]).to be_an(Array)

      classify_run = pipeline_run.action_runs
        .joins(:step_action)
        .find_by(step_actions: { action_id: classify_action.id })

      expect(classify_run.status).to eq("completed")
      expect(classify_run.output).to have_key("result")
      expect(classify_run.output["result"]).to have_key("results")
    end
    # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength

    it "uses the HTTP trigger endpoint to enqueue a run and redirects with notice" do
      allow(PipelineRunJob).to receive(:perform_later)

      post run_orchestration_pipeline_path(pipeline)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      follow_redirect!
      expect(response.body).to include("Pipeline run triggered.")
      expect(PipelineRunJob).to have_received(:perform_later).with(Orchestration::PipelineRun.last.id)
    end
  end

  describe "edit: updating an existing pipeline's metadata, steps, and action attachments" do
    let!(:ingest_action) do
      create(:orchestration_action, name: "Transform Data", agent_class: "Orchestration::IngestionExecutor",
        params: { "operations" => [ { "type" => "pick", "keys" => [ "interviews" ] } ] })
    end
    let!(:pipeline) { create(:orchestration_pipeline, name: "Job Application Pipeline", enabled: true) }
    let!(:fetch_step) { create(:orchestration_step, pipeline: pipeline, name: "Fetch Interviews", position: 1) }
    let!(:classify_step) { create(:orchestration_step, pipeline: pipeline, name: "Classify Emails", position: 2) }
    let!(:fetch_step_action) do
      query_action = create(:orchestration_action, name: "Query Interviews", agent_class: "Orchestration::QueryExecutor",
        params: { "table" => "interviews", "column_name" => "status", "column_values" => [ "screening" ] })
      create(:orchestration_step_action, step: fetch_step, action: query_action, position: 1)
    end

    before do
      classify_action = create(:orchestration_action, name: "Classify Emails", agent_class: "Emails::ClassifyAgent")
      create(:orchestration_step_action, step: classify_step, action: classify_action, position: 1)
    end

    it "updates pipeline name and description" do
      patch orchestration_pipeline_path(pipeline), params: {
        orchestration_pipeline: {
          name: "Updated Job Application Pipeline",
          description: "Enhanced with data transformation"
        }
      }

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      pipeline.reload
      expect(pipeline.name).to eq("Updated Job Application Pipeline")
      expect(pipeline.description).to eq("Enhanced with data transformation")
    end

    # rubocop:disable RSpec/ExampleLength
    it "renames an existing step and updates its input_mapping" do
      patch orchestration_pipeline_step_path(pipeline, classify_step), params: {
        orchestration_step: {
          name: "AI Classification",
          input_mapping: '{"emails":{"from_step":"Fetch Interviews","path":"interviews"}}'
        }
      }

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      classify_step.reload
      expect(classify_step.name).to eq("AI Classification")
      expect(classify_step.input_mapping).to eq(
        "emails" => { "from_step" => "Fetch Interviews", "path" => "interviews" }
      )
    end
    # rubocop:disable RSpec/ExampleLength

    # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
    it "adds a new step with a service-object action at the end" do
      expect {
        post orchestration_pipeline_steps_path(pipeline), params: {
          orchestration_step: { name: "Transform Data" }
        }
      }.to change(Orchestration::Step, :count).by(1)

      transform_step = Orchestration::Step.find_by!(name: "Transform Data")
      expect(transform_step.position).to eq(3)

      post orchestration_pipeline_step_step_actions_path(pipeline, transform_step), params: {
        orchestration_step_action: {
          action_id: ingest_action.id,
          params: '{"operations":[{"type":"pick","keys":["interviews"]}]}'
        }
      }

      transform_step.reload
      expect(transform_step.step_actions.count).to eq(1)
      step_action = transform_step.step_actions.first
      expect(step_action.action).to eq(ingest_action)
      expect(step_action.params).to eq("operations" => [ { "type" => "pick", "keys" => [ "interviews" ] } ])
    end
    # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength

    it "removes a step from the pipeline" do
      expect {
        delete orchestration_pipeline_step_path(pipeline, classify_step)
      }.to change(Orchestration::Step, :count).by(-1)
        .and change(Orchestration::StepAction, :count).by(-1)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(pipeline.reload.steps.pluck(:name)).to eq([ "Fetch Interviews" ])
    end

    it "reorders steps by moving a step down" do
      patch move_down_orchestration_pipeline_step_path(pipeline, fetch_step)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(fetch_step.reload.position).to eq(2)
      expect(classify_step.reload.position).to eq(1)
    end

    it "reorders steps by moving a step up" do
      patch move_up_orchestration_pipeline_step_path(pipeline, classify_step)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(classify_step.reload.position).to eq(1)
      expect(fetch_step.reload.position).to eq(2)
    end

    # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
    it "detaches an action from a step and attaches a different one" do
      expect {
        delete orchestration_pipeline_step_step_action_path(pipeline, fetch_step, fetch_step_action)
      }.to change(Orchestration::StepAction, :count).by(-1)

      expect(fetch_step.reload.step_actions.count).to eq(0)

      post orchestration_pipeline_step_step_actions_path(pipeline, fetch_step), params: {
        orchestration_step_action: { action_id: ingest_action.id }
      }

      expect(fetch_step.reload.step_actions.count).to eq(1)
      expect(fetch_step.step_actions.first.action).to eq(ingest_action)
    end
    # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength

    it "toggles a step's enabled state" do
      patch toggle_orchestration_pipeline_step_path(pipeline, fetch_step)

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      expect(fetch_step.reload.enabled).to be false

      patch toggle_orchestration_pipeline_step_path(pipeline, fetch_step)

      expect(fetch_step.reload.enabled).to be true
    end

    it "disables then re-enables the pipeline" do
      patch toggle_orchestration_pipeline_path(pipeline)
      expect(pipeline.reload.enabled).to be false

      patch toggle_orchestration_pipeline_path(pipeline)
      expect(pipeline.reload.enabled).to be true
    end
  end
end
