
module RuboCop
  module Cop
    module App
      # Forbids HTML building in helpers; structure belongs in ViewComponents.
      class NoHtmlBuildingInHelper < Base
        MSG = "Do not build HTML in helpers with `%<method>s`; use a ViewComponent instead."

        FORBIDDEN_METHODS = %i[content_tag concat].freeze

        def on_send(node)
          return unless helper_file?

          if FORBIDDEN_METHODS.include?(node.method_name) && node.receiver.nil?
            add_offense(node, message: format(MSG, method: node.method_name))
          elsif tag_builder_call?(node)
            add_offense(node, message: format(MSG, method: "tag.#{node.method_name}"))
          end
        end

        private

        def helper_file?
          processed_source.path.include?("app/helpers/")
        end

        def tag_builder_call?(node)
          receiver = node.receiver
          receiver&.send_type? &&
            receiver.method_name == :tag &&
            receiver.receiver.nil?
        end
      end
    end
  end
end
