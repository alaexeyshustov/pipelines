
module UI
  class TableComponent
    class CellComponentPreview < ViewComponent::Preview
      def default
        render(UI::TableComponent::CellComponent.new.with_content("Cell content"))
      end

      def strong
        render(UI::TableComponent::CellComponent.new(variant: :strong).with_content("Bold content"))
      end

      def muted
        render(UI::TableComponent::CellComponent.new(variant: :muted).with_content("Muted content"))
      end

      def mono
        render(UI::TableComponent::CellComponent.new(variant: :mono).with_content("mono-content"))
      end
    end
  end
end
