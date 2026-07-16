
module UI
  class PaginationComponent < ViewComponent::Base
    def initialize(pagy:)
      @pagy = pagy
    end

    def render?
      @pagy.last > 1
    end

    # rubocop:disable Rails/OutputSafety
    def call
      @pagy.series_nav.html_safe
    end
    # rubocop:enable Rails/OutputSafety
  end
end
