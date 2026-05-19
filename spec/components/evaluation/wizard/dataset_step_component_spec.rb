# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Wizard::DatasetStepComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(form: build_form)) }

  let(:agent_name)  { "Emails::ClassifyAgent" }
  let(:datasets)    { build_list(:evaluation_dataset, 2) }
  let(:draft_token) { "abc123" }

  def build_form(overrides = {})
    instance_double(Evaluation::Wizard::Step3Form,
      agent_name:          agent_name,
      datasets:            datasets,
      draft_token:         draft_token,
      selected_dataset_id: nil,
      **overrides
    )
  end

  it "renders dataset names as selectable options" do
    datasets.each { |d| expect(rendered.text).to include(d.name) }
  end

  it "marks selected dataset when selected_dataset_id provided" do
    selected = create(:evaluation_dataset)
    rendered = render_inline(described_class.new(form: build_form(datasets: [ selected ], selected_dataset_id: selected.id)))
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
