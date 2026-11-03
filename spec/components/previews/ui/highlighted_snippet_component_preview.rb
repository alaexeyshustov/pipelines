module UI
  class HighlightedSnippetComponentPreview < ViewComponent::Preview
    def default
      render(UI::HighlightedSnippetComponent.new(snippet: "…reply about the [[interview]] on Monday…"))
    end
  end
end
