# frozen_string_literal: true

module UI
  class BatchActionComponentPreview < ViewComponent::Preview
    def button_neutral
      render(UI::BatchActionComponent.new(
        type: :button,
        label: "Archive",
        url: "/interviews/batch",
        action: "archive",
        variant: :neutral
      ))
    end

    def button_danger_with_confirm
      render(UI::BatchActionComponent.new(
        type: :button,
        label: "Delete Selected",
        url: "/interviews/batch",
        action: "delete",
        variant: :danger,
        confirm: "Delete all selected interviews?"
      ))
    end

    def button_no_require_selection
      render(UI::BatchActionComponent.new(
        type: :button,
        label: "Export All",
        url: "/interviews/batch",
        action: "export",
        variant: :secondary,
        require_selection: false
      ))
    end

    def dialog_neutral
      render(UI::BatchActionComponent.new(
        type: :dialog,
        label: "Archive Selected",
        dialog_title: "Archive interviews?",
        url: "/interviews/batch",
        action: "archive",
        confirm: "Archive",
        variant: :neutral
      ))
    end

    def dialog_danger
      render(UI::BatchActionComponent.new(
        type: :dialog,
        label: "Delete Selected",
        dialog_title: "Delete interviews?",
        url: "/interviews/batch",
        action: "delete",
        confirm: "Yes, delete",
        variant: :danger
      ))
    end

    def raw
      render(UI::BatchActionComponent.new) do
        '<button type="button" class="px-3 py-1.5 text-xs font-medium text-purple-700 bg-purple-50 border border-purple-200 rounded-lg">Custom</button>'.html_safe
      end
    end
  end
end
