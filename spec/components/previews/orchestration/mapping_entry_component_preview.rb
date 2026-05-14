# frozen_string_literal: true

module Orchestration
  class MappingEntryComponentPreview < ViewComponent::Preview
    def default
      row = Orchestration::InputMappingComponent::MappingRow.new(
        mapping_key:  "email_body",
        current_from: "_initial",
        current_path: "body",
        path_opts:    [["body", "body"], ["subject", "subject"]]
      )
      from_options = [["_initial", "_initial"], ["classification", "classification"]]

      render(Orchestration::MappingEntryComponent.new(row: row, from_options: from_options))
    end

    def with_text_path_field
      row = Orchestration::InputMappingComponent::MappingRow.new(
        mapping_key:  "custom_key",
        current_from: "_initial",
        current_path: "some.nested.path",
        path_opts:    nil
      )
      from_options = [["_initial", "_initial"]]

      render(Orchestration::MappingEntryComponent.new(row: row, from_options: from_options))
    end
  end
end
