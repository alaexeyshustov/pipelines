# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::InputMappingComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:pipeline) { build_stubbed(:orchestration_pipeline, id: 1) }
  let(:step) { build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, position: 1, enabled: true) }
  let(:action) { build_stubbed(:orchestration_action, name: "Classify Emails") }
  let(:step_action) do
    build_stubbed(
      :orchestration_step_action,
      id: 99,
      step: step,
      action: action,
      output_key: "classify_emails",
      input_mapping: { "email" => { "from" => "_initial", "path" => "body" } }
    )
  end
  let(:component) do
    described_class.new(
      step_action: step_action,
      pipeline: pipeline,
      step: step,
      upstream_schemas: { "_initial" => { "properties" => { "body" => { "type" => "string" } } } }
    )
  end

  it "submits through the top-level page so flash messages are visible" do
    form = rendered.css("form").first

    expect(form["data-turbo-frame"]).to eq("_top")
  end
end
