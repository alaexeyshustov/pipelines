# frozen_string_literal: true

module Orchestration
  class NewMappingEntryComponent < ViewComponent::Base
    def initialize(from_options:)
      @from_options = from_options
    end
  end
end
