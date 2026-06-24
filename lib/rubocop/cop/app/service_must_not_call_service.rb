# frozen_string_literal: true

module RuboCop
  module Cop
    module App
      # Services must not call another service's .call inside their own call method.
      # Multi-service orchestration belongs in a job or orchestration service.
      class ServiceMustNotCallService < Base
        MSG = "Do not call another service's `.call` from within a service; " \
              "use a job or orchestration service instead."

        def on_send(node)
          return unless service_file?
          return unless node.method_name == :call
          return unless node.receiver&.const_type?

          add_offense(node, message: MSG)
        end

        private

        def service_file?
          processed_source.path.include?("app/services/")
        end
      end
    end
  end
end
