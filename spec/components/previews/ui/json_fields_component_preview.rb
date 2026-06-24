# frozen_string_literal: true

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

    def with_prefix
      render(UI::JsonFieldsComponent.new(form: nil, schema: SCHEMA, name_prefix: "record"))
    end
  end
end
