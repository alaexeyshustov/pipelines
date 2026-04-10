# frozen_string_literal: true

module UI
  class TableComponent
    class RowComponent < ViewComponent::Base
      def call
        content_tag(:tr, content, class: "hover:bg-gray-50 transition-colors")
      end
    end
  end
end
