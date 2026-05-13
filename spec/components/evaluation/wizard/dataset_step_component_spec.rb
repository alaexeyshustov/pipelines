# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Wizard::DatasetStepComponent, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(
      agent_name: agent_name,
      datasets: datasets,
      draft_token: draft_token
    ))
  end

  let(:agent_name) { "Emails::ClassifyAgent" }
  let(:datasets) { build_list(:leva_dataset, 2) }
  let(:draft_token) { "abc123" }


  it "renders dataset names as selectable options" do
    datasets.each { |d| expect(rendered.text).to include(d.name) }
  end

  it "marks selected dataset when selected_dataset_id provided" do
    selected = create(:leva_dataset)
    rendered = render_inline(described_class.new(
      agent_name: agent_name,
      datasets: [ selected ],
      selected_dataset_id: selected.id,
      draft_token: draft_token
    ))
    radio = rendered.css("input[type='radio'][value='#{selected.id}']").first
    expect(radio["checked"]).to be_present
  end

  it "renders a synthetic dataset generation section" do
    expect(rendered.text).to include("Synthetic")
  end

  it "renders a Next button" do
    expect(rendered.css("button[type='submit']").text).to include("Next")
  end
end
