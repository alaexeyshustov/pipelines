require "rails_helper"

RSpec.describe Orchestration::StepsListComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(pipeline:, steps: pipeline.steps_with_actions.to_a, actions: Orchestration::Action.all.to_a)) }

  let(:pipeline) { create(:orchestration_pipeline) }
  let(:list_step) { create(:orchestration_step, pipeline:, position: 1, name: "Classify emails") }
  let(:embed_step) { create(:orchestration_step, pipeline:, position: 2, name: "Embed emails") }
  let(:classify) { create(:orchestration_action, :service_kind, agent_class: "Orchestration::Executors::EmailsClassify") }
  let(:embed) { create(:orchestration_action, :service_kind, agent_class: "Orchestration::Executors::EmailsEmbed") }
  let(:mapped_path) { "tagged" }

  before do
    create(:orchestration_step_action, step: list_step, position: 1, output_key: "classify_emails", action: classify,
                                       input_mapping: { "email_ids" => { "value" => [] } })
    create(:orchestration_step_action, step: embed_step, position: 1, output_key: "embed_emails", action: embed,
                                       input_mapping: { "email_ids" => { "from" => "classify_emails", "path" => mapped_path } })
  end

  it "offers the paths of a service step's output_schema to the steps after it" do
    options = rendered.css("select[data-testid='path-select'] option").pluck("value")

    expect(options).to include("tagged", "untagged", "failed")
  end

  it "offers the service step's output key as a from option" do
    expect(rendered.css("select[data-testid='from-select'] option[value='classify_emails']")).to be_present
  end

  it "shows no validation error for a path that exists in the service output" do
    expect(rendered.css("[data-testid='validity-badge']").map { |badge| badge.text.strip }).to all(eq("Valid"))
  end

  context "when the mapped path is not in the service output schema" do
    let(:mapped_path) { "nonexistent" }

    it "marks the step as having an error" do
      badges = rendered.css("[data-testid='validity-badge']").map { |badge| badge.text.strip }

      expect(badges).to include("1 error")
    end
  end
end
