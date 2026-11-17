require "rails_helper"

RSpec.describe Orchestration::AgentToolsComponent, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(available_tools: %w[Records::InsertRowsTool Emails::FetchTool], selected: %w[Emails::FetchTool]))
  end

  it "checks only the selected tools" do
    checked = rendered.css("input[type='checkbox'][checked]").pluck("value")
    expect(checked).to eq(%w[Emails::FetchTool])
  end
end
