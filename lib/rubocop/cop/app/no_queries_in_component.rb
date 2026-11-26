module RuboCop
  module Cop
    module App
      # Forbids ActiveRecord queries inside ViewComponents; callers pass loaded data.
      #
      # Heuristic: flags query methods on a model constant (`Metric.where`) or on an
      # association reader (`@experiment.samples.count`), not on passed-in collections.
      class NoQueriesInComponent < Base
        MSG = "Do not query ActiveRecord in a component; have the caller pass loaded data.".freeze
        QUERY_METHODS = %i[
          where order reorder find_by find_by! pluck count exists? includes joins left_joins
          limit offset none distinct group sum maximum minimum average find_each
        ].freeze
        CONSTANT_QUERY_METHODS = (QUERY_METHODS + %i[find all first last]).freeze

        def on_send(node)
          return unless component_file?
          return if chained_into_query?(node)
          return if enumerable_call?(node)
          return unless query?(node)

          add_offense(node, message: MSG)
        end

        private

        def component_file?
          processed_source.path.include?("app/components/") &&
            !processed_source.path.include?("_preview.rb")
        end

        def query?(node)
          receiver = node.receiver
          return false unless receiver

          if model_chain?(receiver)
            CONSTANT_QUERY_METHODS.include?(node.method_name)
          else
            QUERY_METHODS.include?(node.method_name) && association_reader?(receiver)
          end
        end

        # A later query in the same chain reports the whole expression once.
        def chained_into_query?(node)
          parent = node.parent
          parent&.send_type? && parent.receiver.equal?(node) && QUERY_METHODS.include?(parent.method_name)
        end

        def enumerable_call?(node)
          parent = node.parent
          return true if parent&.block_type? && parent.send_node.equal?(node)

          node.arguments.any?(&:block_pass_type?)
        end

        def model_chain?(node)
          current = node
          current = current.receiver while current&.send_type?
          return false unless current&.const_type?

          name = current.short_name.to_s
          name != name.upcase
        end

        def association_reader?(node)
          node.send_type? && node.arguments.empty? && node.method_name != :[] && !node.receiver.nil?
        end
      end
    end
  end
end
