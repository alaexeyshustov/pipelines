
module RuboCop
  module Cop
    module App
      class ServiceMustHaveClassCall < Base
        MSG = "Service classes must define `def self.call`."

        def on_class(node)
          return unless service_file?
          return if node.each_ancestor(:class).any?
          return if error_class?(node)
          return if has_class_call?(node)

          add_offense(node, message: MSG)
        end

        private

        def service_file?
          processed_source.path.include?("app/services/")
        end

        def error_class?(node)
          node.parent_class&.const_name == "StandardError"
        end

        def has_class_call?(node)
          body = node.body
          return false unless body

          children = body.begin_type? ? body.children : [ body ]
          children.any? do |child|
            if child.class_type?
              has_class_call?(child)
            else
              child.defs_type? && child.method_name == :call && child.receiver.self_type?
            end
          end
        end
      end
    end
  end
end
