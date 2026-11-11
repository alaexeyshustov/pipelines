module Tags
  class TagCardComponentPreview < ViewComponent::Preview
    def default
      tag = Tag.new(id: 1, name: "finance")
      subtags = %w[bank invoice tax].map { |name| Subtag.new(tag:, name:) }
      render(Tags::TagCardComponent.new(tag:, subtags:, form_url: "/tags/1/subtags"))
    end
  end
end
