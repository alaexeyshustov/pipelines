
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

  let(:response_body) do
    {
      id: "cmpl-test",
      object: "chat.completion",
      model: "mistral-large-latest",
      choices: [ {
        index: 0,
        message: {
          role: "assistant",
          content: '{"results":[{"id":"email-1","tags":["job","application"]}]}',
          tool_calls: nil
        },
        finish_reason: "stop"
      } ],
      usage: { prompt_tokens: 50, completion_tokens: 20, total_tokens: 70 }
    }
  end

  let(:mistral_stub) do
    stub_request(:post, %r{api\.mistral\.ai/v1/chat/completions})
      .to_return(
        status: 200,
        body: response_body.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  before do
    mistral_stub
    create(:orchestration_step_action,
           step: step,
           action: classify_action,
           position: 1)
  end

  it "runs a pipeline through the dialog UI and shows the completed run" do # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    visit orchestration_pipeline_path(pipeline)

    click_button "Run now"
    expect(page).to have_selector("dialog[open]", wait: 2)

    within("dialog[open]") do
      fill_in "Email body", with: "Congratulations on your application"
      click_button "Run"
    end

    expect(page).to have_content("Pipeline run triggered", wait: 5)
    expect(mistral_stub).to have_been_requested.times(1)

    pipeline_run = Orchestration::PipelineRun.last
    expect(pipeline_run.status).to eq("completed")

    click_link "Run History"
    expect(page).to have_content("Completed", wait: 5)
  end
end
