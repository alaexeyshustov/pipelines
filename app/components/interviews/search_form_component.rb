# frozen_string_literal: true

module Interviews
  class SearchFormComponent < UI::SearchFormComponent
    def initialize(url:, query:, clear_url:)
      super(url: url, query: query, clear_url: clear_url, placeholder: "Search by company or job title…")
    end
  end
end
