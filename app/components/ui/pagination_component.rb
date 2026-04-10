# frozen_string_literal: true

module UI
  class PaginationComponent < ViewComponent::Base
    def initialize(pagy:)
      @pagy = pagy
    end

    def render?
      @pagy.last > 1
    end

    def call
      @pagy.series_nav.html_safe
    end
  end
end
