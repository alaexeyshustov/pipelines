module UI
  class LegacyTableComponent
    class CellComponentPreview < ViewComponent::Preview
      def default
        render(UI::LegacyTableComponent::CellComponent.new.with_content("Cell content"))
      end

      def strong
        render(UI::LegacyTableComponent::CellComponent.new(variant: :strong).with_content("Bold content"))
      end

      def muted
        render(UI::LegacyTableComponent::CellComponent.new(variant: :muted).with_content("Muted content"))
      end

      def mono
        render(UI::LegacyTableComponent::CellComponent.new(variant: :mono).with_content("mono-content"))
      end
    end
  end
end
