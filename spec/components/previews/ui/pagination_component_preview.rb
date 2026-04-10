# frozen_string_literal: true

module UI
  class PaginationComponentPreview < ViewComponent::Preview
    # @param count number
    # @param page number
    def default(count: 150, page: 3)
      pagy = Pagy.new(count: count.to_i, limit: 20, page: page.to_i)
      render(UI::PaginationComponent.new(pagy: pagy))
    end

    def single_page
      pagy = Pagy.new(count: 5, limit: 20, page: 1)
      render(UI::PaginationComponent.new(pagy: pagy))
    end
  end
end
