module RuboCop
  module Cop
    module App
      # Forbids jobs, mail and LLM calls inside `aasm` blocks; AASM callbacks may only normalize data.
      class NoSideEffectAasmCallbacks < Base
        MSG = "Do not trigger jobs, mail or LLM calls from AASM; the service or job that fires the event does that."
        SIDE_EFFECT_METHODS = %i[perform_later perform_now deliver_later deliver_now].freeze
        SIDE_EFFECT_CONSTANTS = %i[RubyLLM].freeze

        def on_block(node)
          return unless aasm_block?(node)

          node.each_descendant(:send, :const) do |child|
            add_offense(child, message: MSG) if side_effect?(child)
          end
        end

        private

        def aasm_block?(node)
          send_node = node.send_node
          send_node.method_name == :aasm && send_node.receiver.nil?
        end

        def side_effect?(node)
          if node.send_type?
            SIDE_EFFECT_METHODS.include?(node.method_name)
          else
            node.namespace.nil? && SIDE_EFFECT_CONSTANTS.include?(node.short_name)
          end
        end
      end
    end
  end
end
