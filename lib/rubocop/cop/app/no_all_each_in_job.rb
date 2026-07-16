
module RuboCop
  module Cop
    module App
      # Forbids .all.each in job classes; use find_each for memory-safe batch iteration.
      class NoAllEachInJob < Base
        MSG = "Do not use `.all.each` in jobs; use `find_each` for memory-safe batch iteration."

        def on_send(node)
          return unless job_file?
          return unless node.method_name == :each
          return unless node.receiver&.send_type? && node.receiver.method_name == :all

          add_offense(node, message: MSG)
        end

        private

        def job_file?
          processed_source.path.include?("app/jobs/")
        end
      end
    end
  end
end
