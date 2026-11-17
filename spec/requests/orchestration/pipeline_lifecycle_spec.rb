require "rails_helper"

# Integration test covering the full pipeline lifecycle:
# 1. Setup – create actions, pipeline, steps, and step_action attachments via HTTP
# 2. Run – execute PipelineRunner with a service-object step (QueryExecutor, no HTTP)
#              and an agentic step (ClassifyAgent, Mistral API stubbed via VCR cassette)
# 3. Edit    – update pipeline metadata, reorder/add/remove steps, swap action attachments
RSpec.describe "Orchestration::Pipeline lifecycle" do
  describe "setup: creating a pipeline with steps and actions via HTTP" do
    let(:classify_agent) { create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier") }
    let(:pipeline) { Orchestration::Pipeline.find_by!(name: "Job Application Pipeline") }

    def create_action(**attributes)
      post orchestration_actions_path, params: { orchestration_action: attributes }
    end

    def add_step(name, action_name:)
      post orchestration_pipeline_steps_path(pipeline), params: { orchestration_step: { name: } }
      action_id = Orchestration::Action.find_by!(name: action_name).id
      post orchestration_pipeline_step_step_actions_path(pipeline, pipeline.steps.find_by!(name:)),
           params: { orchestration_step_action: { action_id: } }
    end

    before do
      create_action(name: "Query Interviews", kind: "service", agent_class: "Orchestration::Executors::Query",
                    description: "Fetches interviews from the database")
      create_action(name: "Classify Emails", kind: "agent", agent_id: classify_agent.id,
                    description: "Classifies emails using Mistral AI")
      post orchestration_pipelines_path, params: { orchestration_pipeline: { name: "Job Application Pipeline", enabled: true } }
      add_step("Fetch Interviews", action_name: "Query Interviews")
      add_step("Classify Emails", action_name: "Classify Emails")
    end

    it "creates a service-object action and an agentic action" do
      expect(Orchestration::Action.find_by!(name: "Query Interviews").agent_class).to eq("Orchestration::Executors::Query")
      expect(Orchestration::Action.find_by!(name: "Classify Emails").agent).to eq(classify_agent)
    end

    it "creates the enabled pipeline" do
      expect(pipeline.enabled).to be true
    end

    it "adds the steps in order, each with its action" do
      steps = pipeline.steps.includes(step_actions: :action).order(:position).map do |step|
        [ step.name, step.position, step.step_actions.map { |step_action| step_action.action.name } ]
      end

      expect(steps).to eq([ [ "Fetch Interviews", 1, [ "Query Interviews" ] ], [ "Classify Emails", 2, [ "Classify Emails" ] ] ])
    end

    it "shows the full structure on the pipeline page" do
      get orchestration_pipeline_path(pipeline)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Job Application Pipeline", "Fetch Interviews", "Classify Emails", "Query Interviews")
    end
  end

  describe "run: executing a pipeline with service-object and agentic steps" do
    let!(:query_action) do
      create(:orchestration_action, :service_kind,
        name: "Query Interviews",
        agent_class: "Orchestration::Executors::Query")
    end
    let!(:classify_agent) do
      create(:orchestration_agent,
             name: "Orchestration::Agents::EmailsClassifier",
             model: LlmTestBackend.model_for("mistral-large-latest"),
             tools: [ "Records::TempFileTool" ])
    end
    let!(:classify_action) do
      create(:orchestration_action, name: "Classify Emails", agent: classify_agent)
    end
    let!(:pipeline) { create(:orchestration_pipeline, name: "Job Application Pipeline", enabled: true) }
    let!(:fetch_step) { create(:orchestration_step, pipeline: pipeline, name: "Fetch Interviews", position: 1) }
    let!(:classify_step) { create(:orchestration_step, pipeline: pipeline, name: "Classify Emails", position: 2) }

    before do
      create(:orchestration_step_action, step: fetch_step, action: query_action, position: 1,
        input_mapping: {
          "table"         => { "value" => "interviews" },
          "column_name"   => { "value" => "status" },
          "column_values" => { "value" => [ "screening" ] }
        })
      create(:orchestration_step_action, step: classify_step, action: classify_action, position: 1)
    end

    it "completes both steps and records action run outputs", :llm,
       vcr: { cassette_name: "orchestration/pipeline_lifecycle/classify_agent_run" } do
      pipeline_run = Orchestration::PipelineRun.create!(pipeline:, status: "pending", triggered_by: "manual")
      Orchestration::PipelineRunner.new(pipeline_run).run

      expect(pipeline_run.reload).to have_attributes(status: "completed", action_runs: have_attributes(count: 2))
      expect(run_of(pipeline_run, query_action))
        .to have_attributes(status: "completed", output: a_hash_including("interviews" => an_instance_of(Array)))
      expect(run_of(pipeline_run, classify_action))
        .to have_attributes(status: "completed", output: a_hash_including("result" => classify_result))
    end

    def run_of(pipeline_run, action)
      pipeline_run.action_runs.joins(:step_action).find_by(orchestration_step_actions: { action_id: action.id })
    end

    # The agent has no prompt; only the recorded answer is known to be JSON.
    def classify_result
      LlmTestBackend.live? ? anything : a_hash_including("results")
    end

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
      create(:orchestration_action, :service_kind, name: "Transform Data",
        agent_class: "Orchestration::Executors::Ingestion")
    end
    let!(:pipeline) { create(:orchestration_pipeline, name: "Job Application Pipeline", enabled: true) }
    let!(:fetch_step) { create(:orchestration_step, pipeline: pipeline, name: "Fetch Interviews", position: 1) }
    let!(:classify_step) { create(:orchestration_step, pipeline: pipeline, name: "Classify Emails", position: 2) }
    let!(:fetch_step_action) do
      query_action = create(:orchestration_action, :service_kind, name: "Query Interviews",
        agent_class: "Orchestration::Executors::Query")
      create(:orchestration_step_action, step: fetch_step, action: query_action, position: 1)
    end

    before do
      classify_agent = create(:orchestration_agent, name: "Orchestration::Agents::EmailsClassifier")
      classify_action = create(:orchestration_action, name: "Classify Emails", agent: classify_agent)
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

    it "renames an existing step and redirects" do
      patch orchestration_pipeline_step_path(pipeline, classify_step), params: {
        orchestration_step: { name: "AI Classification" }
      }

      expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      classify_step.reload
      expect(classify_step.name).to eq("AI Classification")
    end

    it "adds a new step at the end" do
      expect {
        post orchestration_pipeline_steps_path(pipeline), params: {
          orchestration_step: { name: "Transform Data" }
        }
      }.to change(Orchestration::Step, :count).by(1)

      expect(Orchestration::Step.find_by!(name: "Transform Data").position).to eq(3)
    end

    it "attaches a service-object action to a new step" do
      transform_step = create(:orchestration_step, pipeline:, name: "Transform Data", position: 3)

      post orchestration_pipeline_step_step_actions_path(pipeline, transform_step), params: {
        orchestration_step_action: { action_id: ingest_action.id }
      }

      expect(transform_step.reload.step_actions.map(&:action)).to eq([ ingest_action ])
    end

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

    it "detaches an action from a step and attaches a different one" do
      expect {
        delete orchestration_pipeline_step_step_action_path(pipeline, fetch_step, fetch_step_action)
      }.to change(Orchestration::StepAction, :count).by(-1)

      post orchestration_pipeline_step_step_actions_path(pipeline, fetch_step), params: {
        orchestration_step_action: { action_id: ingest_action.id }
      }

      expect(fetch_step.reload.step_actions.map(&:action)).to eq([ ingest_action ])
    end

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
