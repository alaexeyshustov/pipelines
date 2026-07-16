
require "rails_helper"

RSpec.describe Evaluation::Wizard::StepNavComponent, type: :component do
  it "renders all 4 step labels" do
    rendered = render_inline(described_class.new(current_step: 1))
    %w[Metrics Dataset].each { |label| expect(rendered.text).to include(label) }
    expect(rendered.text).to include("Agent")
    expect(rendered.text).to include("Review")
  end

  it "marks current step as active" do
    rendered = render_inline(described_class.new(current_step: 2))
    expect(rendered.css("[data-testid='step-active']").text).to include("Metrics")
  end

  it "marks prior steps as complete" do
    rendered = render_inline(described_class.new(current_step: 3))
    expect(rendered.css("[data-testid='step-complete']").length).to eq(2)
  end

  it "marks future steps as upcoming" do
    rendered = render_inline(described_class.new(current_step: 1))
    expect(rendered.css("[data-testid='step-upcoming']").length).to eq(3)
  end
end
