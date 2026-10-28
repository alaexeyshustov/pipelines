module UI
  class LegacyTableComponent < ViewComponent::Base
    class BatchActionSlot < ViewComponent::Base
      def call
        content
      end
    end
  end
end
