# frozen_string_literal: true

module UI
  class SearchFormComponent < ViewComponent::Base
    def initialize(url:, query:, clear_url:, placeholder: "Search…")
      @url = url
      @query = query
      @clear_url = clear_url
      @placeholder = placeholder
    end

    def query_present?
      @query.present?
    end
  end
end
