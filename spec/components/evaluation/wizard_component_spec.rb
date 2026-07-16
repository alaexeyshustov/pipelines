
require "rails_helper"

RSpec.describe Evaluation::WizardComponent, type: :component do
  let(:token) { "test_token_abc" }
  let(:wizard_form) { Evaluation::WizardForm.new(wizard_token: token) }

  def render_at_step(step)
    create(:evaluation_wizard_draft, session_token: token, step: step, payload: { "agent_name" => "TestAgent" })
    render_inline(described_class.new(current_step: step, form: wizard_form))
  end

  it "renders step 1 content (experiment name input) when current_step is 1" do
    rendered = render_at_step(1)
    expect(rendered.css("input[name*='experiment_name']")).to be_present
  end

  it "renders step 2 content (metrics next button) when current_step is 2" do
    rendered = render_at_step(2)
    expect(rendered.css("form[action*='/evaluation/experiments'] button[type='submit']").text).to include("Next")
  end

  it "renders the step navigation" do
    create(:evaluation_wizard_draft, session_token: token, step: 1)
    rendered = render_inline(described_class.new(current_step: 1, form: wizard_form))
    expect(rendered.text).to include("Agent")
  end
end
