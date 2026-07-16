
module RuboCop
  module Cop
    module App
      # Forbids test doubles (double, instance_double, spy) in specs.
      # Use real objects or fake implementations instead.
      class NoTestDoubles < Base
        MSG = "Do not use `%<method>s`; use real objects or fake implementations instead."

        FORBIDDEN = %i[double instance_double spy].freeze

        def on_send(node)
          return unless spec_file?
          return unless FORBIDDEN.include?(node.method_name)
          return unless node.receiver.nil?

          add_offense(node, message: format(MSG, method: node.method_name))
        end

        private

        def spec_file?
          processed_source.path.include?("spec/")
        end
      end
    end
  end
end
