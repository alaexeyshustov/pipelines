
module UI
  class TableComponent
    class RowComponentPreview < ViewComponent::Preview
      def default
        render(UI::TableComponent::RowComponent.new.with_content(
          '<td class="px-4 py-3">Acme Corp</td><td class="px-4 py-3">Active</td>'.html_safe
        ))
      end
    end
  end
end
