
module RuboCop
  module Cop
    module App
      # Only `call` and `initialize` may be public instance methods in a service.
      class ServiceSinglePublicMethod < Base
        MSG = "Service public instance methods must be limited to `call` and `initialize`; `%<method>s` is not allowed."

        ALLOWED = %i[call initialize].freeze

        def on_class(node)
          return unless service_file?
          return if node.each_ancestor(:class).any?

          body = node.body
          return unless body

          children = body.begin_type? ? body.children : [ body ]
          check_class_methods(children)
        end

        private

        def check_class_methods(children)
          visibility = :public
          children.each do |child|
            if visibility_toggle?(child)
              visibility = child.method_name
            elsif child.def_type? && visibility == :public && !ALLOWED.include?(child.method_name)
              add_offense(child, message: format(MSG, method: child.method_name))
            end
          end
        end

        def service_file?
          processed_source.path.include?("app/services/")
        end

        def visibility_toggle?(node)
          node.send_type? &&
            %i[private protected public].include?(node.method_name) &&
            node.receiver.nil? &&
            node.arguments.empty?
        end
      end
    end
  end
end
