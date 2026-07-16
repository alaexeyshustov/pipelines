
require "rails_helper"

RSpec.describe Evaluation::Wizard::DatasetStepComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(form: build_form)) }

  let(:agent_name)  { "Emails::ClassifyAgent" }
  let!(:datasets)   { create_list(:evaluation_dataset, 2, agent_name: agent_name) }
  let(:draft_token) { "abc123" }

  def build_form(overrides = {})
    payload = {
      "agent_name" => overrides.fetch(:agent_name, agent_name),
      "dataset_id" => overrides.fetch(:selected_dataset_id, nil)
    }
    Evaluation::Wizard::Step3Form.new(
      draft_payload: payload,
      draft_token:   overrides.fetch(:draft_token, draft_token)
    )
  end

  it "renders dataset names as selectable options" do
    datasets.each { |d| expect(rendered.text).to include(d.name) }
  end

  it "marks selected dataset when selected_dataset_id provided" do
    selected = create(:evaluation_dataset, agent_name: agent_name)
    rendered = render_inline(described_class.new(form: build_form(selected_dataset_id: selected.id)))
    radio = rendered.css("input[type='radio'][value='#{selected.id}']").first
    expect(radio["checked"]).to be_present
  end

  it "renders a Resync button for each dataset" do
    resync_buttons = rendered.css("button[data-action='dialog#open']")
    expect(resync_buttons.size).to eq(datasets.size)
  end

  it "renders a resync dialog for each dataset" do
    datasets.each do |d|
      expect(rendered.css("dialog").text).to include(d.name)
    end
  end

  it "renders a synthetic dataset generation section" do
    expect(rendered.text).to include("Synthetic")
  end

  it "renders a Next button" do
    expect(rendered.css("button[type='submit']").text).to include("Next")
  end
end
