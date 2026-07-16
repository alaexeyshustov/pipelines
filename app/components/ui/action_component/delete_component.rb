
module UI
  class ActionComponent
    class DeleteComponent < ViewComponent::Base
      def initialize(label:, url:, confirm: nil)
        @label   = label
        @url     = url
        @confirm = confirm
      end

      def css_classes
        ActionComponent::DELETE_CLASSES
      end
    end
  end
end
