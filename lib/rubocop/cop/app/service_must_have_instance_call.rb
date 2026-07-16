
module RuboCop
  module Cop
    module App
      class ServiceMustHaveInstanceCall < Base
        MSG = "Service classes must define `def call`."

        def on_class(node)
          return unless service_file?
          return if node.each_ancestor(:class).any?
          return if has_instance_call?(node)

          add_offense(node, message: MSG)
        end

        private

        def service_file?
          processed_source.path.include?("app/services/")
        end

        def has_instance_call?(node)
          body = node.body
          return false unless body

          children = body.begin_type? ? body.children : [ body ]
          children.any? { |child| child.def_type? && child.method_name == :call }
        end
      end
    end
  end
end
