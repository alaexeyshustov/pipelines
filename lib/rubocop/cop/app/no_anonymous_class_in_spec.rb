module RuboCop
  module Cop
    module App
      # Anonymous classes in specs get a name through `stub_const`, so they can be
      # deserialized, constantized and reported by name.
      class NoAnonymousClassInSpec < Base
        MSG = 'Name anonymous classes with `stub_const("Name", Class.new)`.'.freeze

        def on_send(node)
          return unless spec_file?
          return unless anonymous_class?(node)
          return if node.each_ancestor(:send).any? { |ancestor| ancestor.method_name == :stub_const }

          add_offense(node, message: MSG)
        end

        private

        def spec_file?
          processed_source.path.include?("spec/")
        end

        def anonymous_class?(node)
          receiver = node.receiver
          return false unless node.method_name == :new && receiver&.const_type? && receiver.short_name == :Class

          namespace = receiver.namespace
          namespace.nil? || namespace.cbase_type?
        end
      end
    end
  end
end
