# frozen_string_literal: true

module Orchestration
  class MappingEntryComponent < ViewComponent::Base
    with_collection_parameter :row

    def initialize(row:, from_options:)
      @row          = row
      @from_options = from_options
    end

    def path_text_field?
      @row.path_opts.nil?
    end
  end
end
