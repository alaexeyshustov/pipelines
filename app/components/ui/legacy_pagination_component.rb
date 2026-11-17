module UI
  class LegacyPaginationComponent < ViewComponent::Base
    def initialize(pagy:)
      @pagy = pagy
    end

    def render?
      @pagy.last > 1
    end
  end
end
