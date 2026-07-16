
module UI
  class ActionComponent
    class RawComponentPreview < ViewComponent::Preview
      def default
        render(UI::ActionComponent::RawComponent.new.with_content(
          '<button type="button" class="px-4 py-2 text-sm font-medium text-indigo-600 border border-indigo-200 rounded-lg">Custom Action</button>'.html_safe
        ))
      end
    end
  end
end
