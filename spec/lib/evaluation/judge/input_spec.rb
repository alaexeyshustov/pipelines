require "rails_helper"

RSpec.describe Evaluation::Judge::Input do
  let(:experiment) { create(:evaluation_experiment) }
  let(:dataset_sample) { create(:evaluation_dataset_sample, dataset: experiment.dataset, expected_tool_calls: nil) }
  let(:sample) do
    create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample,
                               tool_calls: [ { "tool_name" => "x" } ], output: '{"label":"offer"}')
  end

  it "includes instructions, input, actual tool calls and the parsed output" do
    payload = described_class.call(sample: sample, dataset_sample: dataset_sample)
    expect(payload).to include(
      "instructions" => "System prompt", "input" => dataset_sample.input,
      "actual_tool_calls" => [ { "tool_name" => "x" } ], "output" => { "label" => "offer" }
    )
  end

  it "omits the tool-calling dimension when expected_tool_calls is nil" do
    payload = described_class.call(sample: sample, dataset_sample: dataset_sample)
    expect(payload).not_to have_key("expected_tool_calls")
  end

  it "includes expected_tool_calls and output_schema when present" do
    dataset_sample.update!(expected_tool_calls: [ { "tool_name" => "y" } ])
    sample.prompt.update!(output_schema: { "type" => "object" })
    payload = described_class.call(sample: sample, dataset_sample: dataset_sample)
    expect(payload).to include("expected_tool_calls" => [ { "tool_name" => "y" } ], "output_schema" => { "type" => "object" })
  end

  it "keeps plain-text output as is" do
    sample.update!(output: "not json")
    expect(described_class.call(sample: sample, dataset_sample: dataset_sample)["output"]).to eq("not json")
  end

  it "produces data the native judge accepts" do
    payload = described_class.call(sample: sample, dataset_sample: dataset_sample)
    expect { RubyLLM::Judge::Data.copy(payload) }.not_to raise_error
  end
end
