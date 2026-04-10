# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::JsonFieldsComponent, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(form: form, schema: schema, name_prefix: "initial_input"))
  end

  let(:form) { instance_double(ActionView::Helpers::FormBuilder) }

  let(:schema) do
    {
      "properties" => {
        "name"       => { "type" => "string" },
        "start_date" => { "type" => "string", "format" => "date" },
        "sources"    => { "type" => "array", "items" => { "enum" => %w[gmail yahoo] } },
        "status"     => { "type" => "string", "enum" => %w[active inactive] },
        "count"      => { "type" => "integer" },
        "score"      => { "type" => "number" },
        "enabled"    => { "type" => "boolean" }
      },
      "required" => %w[name start_date]
    }
  end


  describe "text input" do
    it "renders a text input for a plain string field" do
      expect(rendered.css("input[type='text'][name='initial_input[name]']")).to be_present
    end
  end

  describe "date input" do
    it "renders a date input for a date-formatted field" do
      expect(rendered.css("input[type='date'][name='initial_input[start_date]']")).to be_present
    end
  end

  describe "checkboxes" do
    it "renders checkboxes for an array field with enum items" do
      checkboxes = rendered.css("input[type='checkbox'][name='initial_input[sources][]']")
      expect(checkboxes.map { |c| c["value"] }).to match_array(%w[gmail yahoo])
    end
  end

  describe "select" do
    it "renders a select for a string field with enum" do
      select = rendered.css("select[name='initial_input[status]']")
      expect(select).to be_present
    end

    it "renders options for each enum value" do
      options = rendered.css("select[name='initial_input[status]'] option").map { |o| o["value"] }
      expect(options).to include("active", "inactive")
    end
  end

  describe "number input" do
    it "renders a number input for an integer field" do
      expect(rendered.css("input[type='number'][name='initial_input[count]']")).to be_present
    end

    it "renders a number input for a number field" do
      expect(rendered.css("input[type='number'][name='initial_input[score]']")).to be_present
    end
  end

  describe "boolean checkbox" do
    it "renders a single checkbox for a boolean field" do
      checkbox = rendered.css("input[type='checkbox'][name='initial_input[enabled]']")
      expect(checkbox).to be_present
      expect(checkbox.first["value"]).to eq("1")
    end
  end

  describe "labels" do
    it "renders humanized labels for each field" do
      # Select only top-level field labels (not nested checkbox option labels)
      # and normalize whitespace before comparing.
      label_texts = rendered.css("div.mb-4 > label").map do |l|
        l.text.gsub(/[[:space:]]+/, " ").strip.delete("*").strip
      end
      expect(label_texts).to include("Name", "Start date", "Sources", "Status", "Count", "Score", "Enabled")
    end
  end

  describe "required marker" do
    it "marks required fields with an asterisk" do
      required_labels = rendered.css("label abbr[title='required']")
      expect(required_labels.length).to eq(2)
    end
  end

  describe "without a name_prefix" do
    subject(:rendered) { render_inline(described_class.new(form: form, schema: schema)) }

    it "uses just the field name as the input name" do
      expect(rendered.css("input[type='text'][name='name']")).to be_present
    end
  end

  describe "empty schema" do
    subject(:rendered) do
      render_inline(described_class.new(form: form, schema: {}))
    end

    it "renders nothing" do
      expect(rendered.css("div").length).to eq(0)
    end
  end
end
