module UI
  class JsonFieldsComponentPreview < ViewComponent::Preview
    SCHEMA = {
      "properties" => {
        "subject"    => { "type" => "string" },
        "status"     => { "type" => "string", "enum" => %w[pending active archived] },
        "count"      => { "type" => "integer" },
        "active"     => { "type" => "boolean" },
        "applied_on" => { "type" => "string", "format" => "date" }
      },
      "required" => %w[subject status]
    }.freeze

    def default
      render(UI::JsonFieldsComponent.new(form: nil, schema: SCHEMA))
    end

    def with_descriptions_and_hints
      schema = {
        "properties" => {
          "providers" => { "type" => "array", "items" => { "enum" => %w[gmail yahoo] }, "description" => "Mailboxes to read." },
          "date_from" => { "type" => "string", "format" => "date", "description" => "Received on or after." }
        }
      }
      render(UI::JsonFieldsComponent.new(form: nil, schema: schema, hints: { "providers" => "Last synced: gmail 2026-03-20 14:03, yahoo never" }))
    end

    def with_prefix
      render(UI::JsonFieldsComponent.new(form: nil, schema: SCHEMA, name_prefix: "record"))
    end
  end
end
