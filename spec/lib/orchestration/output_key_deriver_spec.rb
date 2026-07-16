
require "rails_helper"

RSpec.describe Orchestration::OutputKeyDeriver do
  let(:step) { create(:orchestration_step) }

  def call(action_name)
    described_class.new(action_name: action_name, step: step).derive
  end

  it "parameterizes a normal action name to snake_case" do
    expect(call("Classify Emails")).to eq("classify_emails")
  end

  it "returns 'action' for a blank name" do
    expect(call("")).to eq("action")
  end

  it "prepends x_ when the base starts with a digit" do
    expect(call("2fast")).to eq("x_2fast")
  end

  it "strips leading underscores via parameterize and produces a valid key" do
    expect(call("_internal")).to eq("internal")
  end

  it "appends a numeric suffix when the base key already exists in the step" do
    create(:orchestration_step_action, step: step, output_key: "classify_emails", position: 1)
    expect(call("Classify Emails")).to eq("classify_emails_2")
  end

  it "increments the suffix until a unique key is found" do
    create(:orchestration_step_action, step: step, output_key: "classify_emails",   position: 1)
    create(:orchestration_step_action, step: step, output_key: "classify_emails_2", position: 2)
    expect(call("Classify Emails")).to eq("classify_emails_3")
  end

  it "allows the same base key in a different step" do
    other_step = create(:orchestration_step)
    create(:orchestration_step_action, step: other_step, output_key: "classify_emails", position: 1)
    expect(call("Classify Emails")).to eq("classify_emails")
  end

  it "treats nil action_name as blank and returns 'action'" do
    expect(call(nil)).to eq("action")
  end
end
