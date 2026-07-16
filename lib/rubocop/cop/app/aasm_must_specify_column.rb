
module RuboCop
  module Cop
    module App
      # aasm blocks must include the `column:` keyword argument.
      class AasmMustSpecifyColumn < Base
        MSG = "Specify the `column:` keyword in `aasm` blocks (e.g., `aasm column: :status do`)."

        def on_block(node)
          return unless model_file?

          send_node = node.children.first
          return unless send_node.method_name == :aasm && send_node.receiver.nil?
          return if has_column_kwarg?(send_node)

          add_offense(send_node, message: MSG)
        end

        alias on_numblock on_block

        private

        def model_file?
          processed_source.path.include?("app/models/")
        end

        def has_column_kwarg?(send_node)
          send_node.arguments.any? do |arg|
            arg.hash_type? && arg.pairs.any? do |pair|
              pair.key.sym_type? && pair.key.value == :column
            end
          end
        end
      end
    end
  end
end
