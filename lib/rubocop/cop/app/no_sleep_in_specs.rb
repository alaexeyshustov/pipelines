module RuboCop
  module Cop
    module App
      # Forbids sleep calls in specs; use Capybara's async helpers or freeze time instead.
      class NoSleepInSpecs < Base
        MSG = "Do not use `sleep` in specs; use Capybara's async helpers or `travel_to` instead.".freeze

        def on_send(node)
          return unless spec_file?
          return unless node.method_name == :sleep
          return unless node.receiver.nil?

          add_offense(node, message: MSG)
        end

        private

        def spec_file?
          processed_source.path.include?("spec/")
        end
      end
    end
  end
end
