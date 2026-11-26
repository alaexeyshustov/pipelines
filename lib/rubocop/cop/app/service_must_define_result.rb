module RuboCop
  module Cop
    module App
      # Services return a `Result = Data.define(...)` value object; a `*Result` name (e.g. `ComparisonResult`) also counts.
      class ServiceMustDefineResult < Base
        extend AutoCorrector

        MSG = "Services must define `Result = Data.define(...)` (or a `*Result` name) and return it.".freeze
        STRUCT_MSG = "Define `%<name>s` with `Data.define`, not `Struct.new`.".freeze

        def on_class(node)
          return unless service_file?
          return if node.each_ancestor(:class).any?
          return if node.parent_class&.const_name == "StandardError"
          return if defines_result?(node)

          add_offense(node.loc.keyword.join(node.identifier.source_range), message: MSG)
        end

        def on_casgn(node)
          return unless service_file?
          return unless result_struct?(node)

          add_offense(node, message: format(STRUCT_MSG, name: node.to_a[1])) do |corrector|
            _, _, value = *node
            corrector.replace(value.receiver.source_range, "Data")
            corrector.replace(value.loc.selector, "define")
          end
        end

        private

        def service_file?
          processed_source.path.include?("app/services/")
        end

        def defines_result?(node)
          body = node.body
          return false unless body

          children = body.begin_type? ? body.children : [ body ]
          children.any? { |child| child.casgn_type? && result_name?(child.to_a[1]) }
        end

        def result_struct?(node)
          _, name, value = *node
          return false unless result_name?(name)
          return false unless value&.send_type? && value.method_name == :new
          return false unless value.receiver&.const_type?

          value.receiver.short_name == :Struct
        end

        def result_name?(name)
          name.to_s.end_with?("Result")
        end
      end
    end
  end
end
