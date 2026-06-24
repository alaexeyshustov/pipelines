# frozen_string_literal: true

module RuboCop
  module Cop
    module App
      # Forbids Current.* access inside ViewComponents; inject current user explicitly.
      class NoCurrentInComponent < Base
        MSG = "Do not access `Current` inside a component; inject the value through the constructor instead."

        def on_send(node)
          return unless component_file?
          return unless current_access?(node)

          add_offense(node, message: MSG)
        end

        private

        def component_file?
          processed_source.path.include?("app/components/") &&
            !processed_source.path.include?("_preview.rb")
        end

        def current_access?(node)
          receiver = node.receiver
          receiver&.const_type? &&
            receiver.short_name == :Current &&
            receiver.namespace.nil?
        end
      end
    end
  end
end
