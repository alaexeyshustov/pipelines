module RuboCop
  module Cop
    module App
      # Specs create records in their final state (factory attributes, traits or `let` overrides)
      # instead of updating them in `before`.
      class NoUpdateInBefore < Base
        MSG = "Create records in their final state instead of updating them in `before`."
        UPDATE_METHODS = %i[update update!].freeze

        def on_send(node)
          return unless spec_file?
          return unless UPDATE_METHODS.include?(node.method_name)
          return if node.receiver.nil?
          return unless node.each_ancestor(:block).any? { |block| before_hook?(block) }

          add_offense(node, message: MSG)
        end

        private

        def spec_file?
          processed_source.path.include?("spec/")
        end

        def before_hook?(block)
          send_node = block.send_node
          send_node.method_name == :before && send_node.receiver.nil?
        end
      end
    end
  end
end
