
module RuboCop
  module Cop
    module App
      # Result constants inside services must use Data.define, not Struct.new.
      class ServiceResultMustUseDataDefine < Base
        extend AutocorrectLogic

        MSG = "Use `Data.define` instead of `Struct.new` for Result value objects."

        def on_casgn(node)
          return unless service_file?
          return unless result_struct?(node)

          add_offense(node, message: MSG)
        end

        def autocorrect(corrector, node)
          _, _, value = *node
          corrector.replace(value.receiver.source_range, "Data")
          corrector.replace(value.loc.selector, "define")
        end

        private

        def service_file?
          processed_source.path.include?("app/services/")
        end

        def result_struct?(node)
          _, name, value = *node
          return false unless name == :Result
          return false unless value&.send_type? && value.method_name == :new
          return false unless value.receiver&.const_type?

          value.receiver.short_name == :Struct
        end
      end
    end
  end
end
