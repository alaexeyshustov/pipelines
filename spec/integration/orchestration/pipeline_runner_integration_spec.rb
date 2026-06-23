# frozen_string_literal: true

# Layer B integration spec: proves PipelineRunner <-> RubyLLM::Agent <-> Mistral HTTP
# integration works for a single classify-only call.
#
# To re-record:
#   rm spec/cassettes/orchestration/pipeline_runner/classify_only.yml
#   RECORD_VCR=1 MISTRAL_API_KEY=$REAL_KEY \
#     bundle exec rspec spec/integration/orchestration/pipeline_runner_integration_spec.rb
# With record: :all, every interaction in the run is overwritten,
# making cassette re-recording idempotent and safe after key rotation.
# The `rm` step above is kept as belt-and-suspenders but is no longer load-bearing.
#
# KNOWN GAP: Multi-fiber fan-out (Sync + Async::Barrier with >1 fiber) is NOT tested here.
# Single-step, single-action pipeline keeps Async::Barrier at degree-one.

require "rails_helper"

RSpec.describe Orchestration::PipelineRunner, type: :integration do
  describe "classify single-step pipeline",
           vcr: {
             cassette_name: "orchestration/pipeline_runner/classify_only",
             match_requests_on: %i[method uri],
             record: ENV.fetch("RECORD_VCR", nil) ? :all : :none
           } do
    let(:pipeline) do
      create(:orchestration_pipeline,
             initial_input_schema: {
               "type" => "object",
               "required" => [],
               "properties" => {
                 "email_body" => { "type" => "string" }
               }
             })
    end

    let(:step) { create(:orchestration_step, pipeline: pipeline, name: "classify", position: 1) }

    let(:classify_agent_record) do
      create(:orchestration_agent,
             name: "Emails::ClassifyAgent",
             model: "mistral-large-latest",
             output_schema: {
               "type" => "object",
               "properties" => {
                 "results" => {
                   "type" => "array",
                   "items" => {
                     "type" => "object",
                     "properties" => {
                       "id" => { "type" => "string" },
                       "tags" => { "type" => "array", "items" => { "type" => "string" } }
                     }
                   }
                 }
               }
             })
    end

    let(:classify_action) do
      create(:orchestration_action, agent: classify_agent_record)
    end

    let(:pipeline_run) do
      create(:orchestration_pipeline_run,
             pipeline: pipeline,
             status: "pending",
             initial_input: { "emails" => [ { "id" => "test-1", "subject" => "Job offer from Acme" } ] })
    end

    before do
      create(:orchestration_step_action,
             step: step,
             action: classify_action,
             position: 1,
             input_mapping: { "emails" => { "from" => "_initial", "path" => "emails" } })
    end

    it "completes the pipeline run end-to-end through real RubyLLM agent" do
      described_class.new(pipeline_run).call
      expect(pipeline_run.reload.status).to eq("completed")
    end

    it "creates exactly one completed ActionRun" do
      described_class.new(pipeline_run).call
      action_runs = Orchestration::ActionRun.where(pipeline_run: pipeline_run)
      expect(action_runs.count).to eq(1)
      expect(action_runs.first.status).to eq("completed")
    end

    it "stores results-keyed output on the ActionRun" do
      described_class.new(pipeline_run).call
      action_run = Orchestration::ActionRun.where(pipeline_run: pipeline_run).first
      expect(action_run.output.keys).to include("results")
    end

    it "has a committed cassette with at least one HTTP interaction" do
      described_class.new(pipeline_run).call
      cassette_path = Rails.root.join(
        "spec/cassettes/orchestration/pipeline_runner/classify_only.yml"
      )
      expect(File).to exist(cassette_path)
      yaml = YAML.safe_load_file(cassette_path, aliases: true)
      expect(yaml.fetch("http_interactions")).not_to be_empty
    end
  end
end
