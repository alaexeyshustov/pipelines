
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

  describe "#path_options_for" do
    subject(:component_instance) do
      described_class.new(
        step_action: step_action,
        pipeline: pipeline,
        step: step,
        upstream_schemas: upstream_schemas
      )
    end

    context "with a flat object schema (no explicit type key)" do
      let(:upstream_schemas) do
        { "_initial" => { "properties" => { "body" => { "type" => "string" }, "subject" => { "type" => "string" } } } }
      end

      it "returns top-level property paths" do
        expect(component_instance.path_options_for("_initial").map(&:first)).to contain_exactly("body", "subject")
      end
    end

    context "with a nested object schema" do
      let(:upstream_schemas) do
        {
          "_initial" => {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string" },
              "address" => {
                "type" => "object",
                "properties" => {
                  "city" => { "type" => "string" },
                  "zip"  => { "type" => "string" }
                }
              }
            }
          }
        }
      end

      it "includes top-level and nested dot-notation paths" do
        paths = component_instance.path_options_for("_initial").map(&:first)
        expect(paths).to include("name", "address", "address.city", "address.zip")
      end
    end

    context "with an array schema" do
      let(:upstream_schemas) do
        {
          "_initial" => {
            "type" => "object",
            "properties" => {
              "rows" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => { "value" => { "type" => "string" } }
                }
              }
            }
          }
        }
      end

      it "includes the array key, index placeholder, and item properties" do
        paths = component_instance.path_options_for("_initial").map(&:first)
        expect(paths).to include("rows", "rows.0", "rows.0.value")
      end
    end

    context "when the schema has no properties" do
      let(:upstream_schemas) { { "_initial" => { "type" => "string" } } }

      it "returns nil" do
        expect(component_instance.path_options_for("_initial")).to be_nil
      end
    end

    context "when the from key is unknown" do
      let(:upstream_schemas) { { "_initial" => { "type" => "object", "properties" => { "x" => { "type" => "string" } } } } }

      it "returns nil" do
        expect(component_instance.path_options_for("unknown_key")).to be_nil
      end
    end
  end
end
