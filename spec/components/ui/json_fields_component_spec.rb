require "rails_helper"

RSpec.describe UI::JsonFieldsComponent, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(form: form, schema: schema, name_prefix: "initial_input"))
  end

  let(:form) { nil }

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
      expect(checkboxes.pluck("value")).to match_array(%w[gmail yahoo])
    end
  end

  describe "select" do
    it "renders a select for a string field with enum" do
      select = rendered.css("select[name='initial_input[status]']")
      expect(select).to be_present
    end

    it "renders options for each enum value" do
      options = rendered.css("select[name='initial_input[status]'] option").pluck("value")
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

  describe "hardcoded string field" do
    subject(:rendered) do
      render_inline(described_class.new(form: form, schema: hardcoded_schema, name_prefix: "initial_input"))
    end

    let(:hardcoded_schema) do
      {
        "properties" => {
          "name"  => { "type" => "string" },
          "topic" => { "type" => "string", "enum" => [ "job applications" ], "format" => "hardcoded" }
        }
      }
    end

    it "does not render an input for the hardcoded field" do
      expect(rendered.css("[name='initial_input[topic]']")).to be_empty
    end

    it "renders a label for the hardcoded field" do
      label_texts = rendered.css("div.mb-4 > label").map { |l| l.text.strip }
      expect(label_texts.join).to include("Topic")
    end

    it "renders the hardcoded value as plain text" do
      expect(rendered.text).to include("job applications")
    end

    it "still renders other fields normally" do
      expect(rendered.css("input[type='text'][name='initial_input[name]']")).to be_present
    end
  end

  describe "hardcoded array field" do
    subject(:rendered) do
      render_inline(described_class.new(form: form, schema: array_schema, name_prefix: "initial_input"))
    end

    let(:array_schema) do
      {
        "properties" => {
          "cols" => { "type" => "array", "format" => "hardcoded",
                      "items" => { "type" => "string", "enum" => [ "company", "job_title" ] } }
        }
      }
    end

    it "does not render an input for the hardcoded array field" do
      expect(rendered.css("[name^='initial_input[cols]']")).to be_empty
    end

    it "renders a label for the hardcoded array field" do
      label_texts = rendered.css("div.mb-4 > label").map { |l| l.text.strip }
      expect(label_texts.join).to include("Cols")
    end

    it "renders the items as a comma-separated string" do
      expect(rendered.text).to include("company, job_title")
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

  describe "descriptions and hints" do
    subject(:rendered) do
      render_inline(described_class.new(form: form, schema: described_schema, name_prefix: "initial_input", hints: hints))
    end

    let(:hints) { { "providers" => "Last synced: gmail 2026-03-20 14:03, yahoo never" } }
    let(:described_schema) do
      {
        "properties" => {
          "providers" => { "type" => "array", "items" => { "enum" => %w[gmail yahoo] }, "description" => "Mailboxes to read." },
          "date_from" => { "type" => "string", "format" => "date", "description" => "Received on or after." },
          "note"      => { "type" => "string" }
        }
      }
    end

    def field_block(label)
      rendered.css("div.mb-4").find { |block| block.at_css("> label")&.text.to_s.include?(label) }
    end

    it "renders a field's description under it" do
      expect(field_block("Providers").text).to include("Mailboxes to read.")
      expect(field_block("Date from").text).to include("Received on or after.")
    end

    it "renders the hint of the field it is keyed by, and only there" do
      expect(field_block("Providers").text).to include("Last synced: gmail 2026-03-20 14:03, yahoo never")
      expect(field_block("Date from").text).not_to include("Last synced")
      expect(field_block("Note").text).not_to include("Last synced")
    end

    it "renders a description and a hint together" do
      block = field_block("Providers").text

      expect(block.index("Mailboxes to read.")).to be < block.index("Last synced")
    end

    it "adds nothing for a field without a description or hint" do
      expect(field_block("Note").css("p, small, span").map(&:text).join.strip).to be_empty
    end

    it "renders a hint for a field that has no description" do
      rendered = render_inline(described_class.new(form: form, schema: described_schema, name_prefix: "initial_input",
                                                   hints: { "note" => "Free text." }))

      block = rendered.css("div.mb-4").find { |div| div.at_css("> label")&.text.to_s.include?("Note") }
      expect(block.text).to include("Free text.")
    end

    it "ignores a hint for a field the schema does not have" do
      rendered = render_inline(described_class.new(form: form, schema: described_schema, name_prefix: "initial_input",
                                                   hints: { "ghost" => "boo" }))

      expect(rendered.text).not_to include("boo")
    end

    it "still renders the inputs" do
      expect(rendered.css("input[type='checkbox'][name='initial_input[providers][]']").size).to eq(2)
      expect(rendered.css("input[type='date'][name='initial_input[date_from]']")).to be_present
    end

    it "works without hints (the keyword is optional)" do
      plain = render_inline(described_class.new(form: form, schema: described_schema, name_prefix: "initial_input"))

      expect(plain.text).to include("Mailboxes to read.")
      expect(plain.text).not_to include("Last synced")
    end

    it "makes no database queries" do
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { rendered }

      expect(count).to eq(0)
    end
  end
end
