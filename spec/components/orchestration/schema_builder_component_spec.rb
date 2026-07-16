
require "rails_helper"

RSpec.describe Orchestration::SchemaBuilderComponent, type: :component do
  def builder_for(schema)
    Orchestration::SchemaBuilder.from_schema(schema)
  end

  subject(:rendered) { render_inline(component) }

  context "with a string schema" do
    let(:component) do
      described_class.new(builder: builder_for("type" => "string", "description" => "A label"))
    end

    it "shows the type select" do
      expect(rendered.css("select[name='new_type']")).to be_present
    end

    it "marks the current type as selected" do
      selected = rendered.css("select[name='new_type'] option[selected]").first
      expect(selected&.text).to eq("string")
    end

    it "shows the description field pre-filled" do
      field = rendered.css("input[name='builder[description]']").first
      expect(field&.attr("value")).to eq("A label")
    end

    it "does not show properties section" do
      expect(rendered.text).not_to include("Add property")
    end

    it "does not show items section" do
      expect(rendered.text).not_to include("Items schema")
    end
  end

  context "with an object schema" do
    let(:schema) do
      {
        "type" => "object",
        "required" => [ "name" ],
        "properties" => {
          "name" => { "type" => "string" },
          "age" => { "type" => "integer" }
        }
      }
    end
    let(:component) { described_class.new(builder: builder_for(schema)) }

    it "shows the add property form" do
      expect(rendered.css("input[name='property_name']")).to be_present
    end

    it "renders each property name" do
      expect(rendered.text).to include("name")
      expect(rendered.text).to include("age")
    end

    it "shows remove buttons for each property" do
      remove_forms = rendered.css("form[action*='remove_property']")
      expect(remove_forms.size).to eq(2)
    end

    it "checks required checkbox for required properties" do
      expect(rendered.css("input[type='checkbox'][name='builder[required_checked]'][checked]")).to be_present
    end
  end

  context "with an array schema" do
    let(:component) do
      described_class.new(
        builder: builder_for("type" => "array", "items" => { "type" => "string" })
      )
    end

    it "shows the items section" do
      expect(rendered.text).to include("Items schema")
    end

    it "renders a nested builder for items" do
      expect(rendered.css(".schema-builder-node").size).to be >= 2
    end
  end

  context "with a string enum schema" do
    let(:component) do
      described_class.new(
        builder: builder_for("type" => "string", "enum" => %w[a b c])
      )
    end

    it "shows the enum textarea" do
      expect(rendered.css("textarea[name='builder[enum_text]']")).to be_present
    end

    it "pre-fills enum values" do
      content = rendered.css("textarea[name='builder[enum_text]']").first&.text
      expect(content).to include("a")
      expect(content).to include("b")
    end
  end

  context "with an integer schema" do
    let(:component) do
      described_class.new(
        builder: builder_for("type" => "integer", "minimum" => 0, "maximum" => 100)
      )
    end

    it "shows the minimum field" do
      field = rendered.css("input[name='builder[minimum]']").first
      expect(field&.attr("value")).to eq("0")
    end

    it "shows the maximum field" do
      field = rendered.css("input[name='builder[maximum]']").first
      expect(field&.attr("value")).to eq("100")
    end
  end

  context "when rendered as root component" do
    let(:component) do
      described_class.new(
        builder: builder_for("type" => "object"),
        json: '{"type":"object"}'
      )
    end

    it "renders the schemaData hidden input" do
      input = rendered.css("input[data-schema-builder-target='schemaData']").first
      expect(input).to be_present
      expect(input&.attr("value")).to eq('{"type":"object"}')
    end
  end

  context "when rendered as nested (non-root) component" do
    let(:component) do
      described_class.new(
        builder: builder_for("type" => "string"),
        path: [ "properties", "name" ],
        json: '{"type":"object"}'
      )
    end

    it "does not render the schemaData hidden input" do
      expect(rendered.css("input[data-schema-builder-target='schemaData']")).to be_empty
    end
  end

  context "when forms include the current json" do
    let(:json_val) { '{"type":"object","properties":{}}' }
    let(:component) do
      described_class.new(
        builder: builder_for({ "type" => "object" }),
        json: json_val
      )
    end

    it "includes json in the add_property form" do
      json_inputs = rendered.css("form[action*='add_property'] input[name='json']")
      expect(json_inputs.first&.attr("value")).to eq(json_val)
    end
  end
end
