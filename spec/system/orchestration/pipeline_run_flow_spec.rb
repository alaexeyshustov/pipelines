# Layer A system spec: proves the full UI → controller → job → runner wiring.
# Mistral is stubbed at the WebMock level with a canned JSON response —
# VCR is NOT used here, removing the "VCR cassette state inside a fiber" risk.
#
# The factory pipeline has initial_input_schema set, which triggers the dialog
# branch of show.html.erb. The non-dialog "Run now" branch is out of scope.
#
# KNOWN GAP: Multi-fiber fan-out is not exercised. Single-step, single-action pipeline.

require "rails_helper"

RSpec.describe "Pipeline run flow", :js do
  let(:pipeline) do
    create(:orchestration_pipeline,
           name: "Test Classification Pipeline",
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
    create(:orchestration_agent, name: "Emails::ClassifyAgent", model: "mistral-large-latest")
  end

  let(:classify_action) do
    create(:orchestration_action, agent: classify_agent_record)
  end

  before do
    create(:orchestration_step_action,
           step: step,
           action: classify_action,
           position: 1)
    # No input_mapping needed — the WebMock stub fires regardless of request body.
  end

  # Mistral at the WebMock level, answering in the ClassifyAgent schema
  # (wire format from spec/cassettes/orchestration/pipeline_lifecycle/classify_agent_run.yml).
  def stub_mistral_classification
    stub_request(:post, %r{api\.mistral\.ai/v1/chat/completions}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: {
        id: "cmpl-test", object: "chat.completion", model: "mistral-large-latest",
        choices: [ {
          index: 0, finish_reason: "stop",
          message: { role: "assistant", content: '{"results":[{"id":"email-1","tags":["job","application"]}]}', tool_calls: nil }
        } ],
        usage: { prompt_tokens: 50, completion_tokens: 20, total_tokens: 70 }
      }.to_json
    )
  end

  # Opens the native <dialog> via Stimulus (stimulus-components/dialog calls showModal()) and submits it.
  def run_from_dialog
    visit orchestration_pipeline_path(pipeline)
    click_button "Run now"
    within("dialog[open]", wait: 2) do
      # Value is irrelevant — the WebMock stub matches by URL only
      fill_in "Email body", with: "Congratulations on your application"
      click_button "Run"
    end
  end

  it "runs a pipeline through the dialog UI and completes it" do
    mistral_stub = stub_mistral_classification
    run_from_dialog

    expect(page).to have_content("Pipeline run triggered", wait: 5)
    expect(mistral_stub).to have_been_requested.times(1)
    expect(Orchestration::PipelineRun.last.status).to eq("completed")
  end

  it "shows the completed run in the run history" do
    stub_mistral_classification
    run_from_dialog
    expect(page).to have_content("Pipeline run triggered", wait: 5)

    click_link "Run History"
    expect(page).to have_content("Completed", wait: 5)
  end
end
