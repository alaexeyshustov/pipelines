# frozen_string_literal: true

module ApplicationMails
  class SearchFormComponent < UI::SearchFormComponent
    # TODO: this class is not needed
    def initialize(url:, query:, clear_url:)
      super(url: url, query: query, clear_url: clear_url, placeholder: "Search by company or job title…")
    end
  end
end
