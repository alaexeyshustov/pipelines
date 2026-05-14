# frozen_string_literal: true

module Orchestration
  class NewMappingEntryComponentPreview < ViewComponent::Preview
    def default
      render(Orchestration::NewMappingEntryComponent.new(from_options: []))
    end

    def with_sources
      render(Orchestration::NewMappingEntryComponent.new(
        from_options: [ [ "_initial", "_initial" ], [ "classification", "classification" ] ]
      ))
    end
  end
end
