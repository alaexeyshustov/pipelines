module Tags
  class TaggingsComponentPreview < ViewComponent::Preview
    def default
      tag = Tag.new(id: 1, name: "finance")
      subtag = Subtag.new(id: 1, tag:, name: "bank")
      tag.subtags.target = [ subtag ]
      tagging = Tagging.new(id: 1, tag:, subtag:, source: "llm", confidence: 0.87)
      render(Tags::TaggingsComponent.new(taggings: [ tagging ], tags: [ tag ], base_url: "/emails/1/taggings"))
    end
  end
end
