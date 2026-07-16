
module RuboCop
  module Cop
    module App
      # Forbids sleep calls in system specs; use Capybara's async helpers instead.
      class NoSleepInSystemSpecs < Base
        MSG = "Do not use `sleep` in system specs; use Capybara's async helpers instead."

        def on_send(node)
          return unless system_spec_file?
          return unless node.method_name == :sleep
          return unless node.receiver.nil?

          add_offense(node, message: MSG)
        end

        private

        def system_spec_file?
          processed_source.path.include?("spec/system/")
        end
      end
    end
  end
end
