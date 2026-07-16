
module Orchestration
  class SchemaBuilderComponentPreview < ViewComponent::Preview
    def empty
      render(Orchestration::SchemaBuilderComponent.new(
        builder: Orchestration::SchemaBuilder.new,
        json: "{}"
      ))
    end

    def string_with_enum
      builder = Orchestration::SchemaBuilder.from_schema(
        "type" => "string",
        "description" => "Application status",
        "enum" => %w[applied interviewing rejected accepted]
      )
      render(Orchestration::SchemaBuilderComponent.new(builder: builder))
    end

    def object_with_properties
      builder = Orchestration::SchemaBuilder.from_schema(
        "type" => "object",
        "description" => "Classification result",
        "required" => [ "status" ],
        "additionalProperties" => false,
        "properties" => {
          "status" => { "type" => "string", "enum" => %w[relevant irrelevant] },
          "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 }
        }
      )
      render(Orchestration::SchemaBuilderComponent.new(builder: builder))
    end

    def nested_object
      builder = Orchestration::SchemaBuilder.from_schema(
        "type" => "object",
        "properties" => {
          "emails" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => {
                "id" => { "type" => "string" },
                "label" => { "type" => "string" }
              }
            }
          }
        }
      )
      render(Orchestration::SchemaBuilderComponent.new(builder: builder))
    end
  end
end
