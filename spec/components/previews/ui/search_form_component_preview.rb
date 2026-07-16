
module UI
  class SearchFormComponentPreview < ViewComponent::Preview
    def default
      render(UI::SearchFormComponent.new(url: "#", query: nil, clear_url: "#"))
    end

    def with_query
      render(UI::SearchFormComponent.new(
        url: "#",
        query: "software engineer",
        clear_url: "#",
        placeholder: "Search emails…"
      ))
    end
  end
end
