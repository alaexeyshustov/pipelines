# frozen_string_literal: true

module UI
  class TableComponent < ViewComponent::Base
    class BatchActionSlot < ViewComponent::Base
      def call
        content
      end
    end
  end
end
