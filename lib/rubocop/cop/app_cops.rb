module RuboCop
  module Cop
    module AppCops
    end
  end
end

require_relative "app/service_must_have_class_call"
require_relative "app/service_must_have_instance_call"
require_relative "app/service_single_public_method"
require_relative "app/service_must_define_result"
require_relative "app/form_object_must_inherit_base_form"
require_relative "app/no_test_doubles"
require_relative "app/no_sleep_in_specs"
require_relative "app/aasm_must_specify_column"
require_relative "app/no_current_in_component"
require_relative "app/component_must_have_preview"
require_relative "app/no_all_each_in_job"
require_relative "app/no_html_building_in_helper"
require_relative "app/no_queries_in_component"
require_relative "app/no_side_effect_aasm_callbacks"
require_relative "app/component_variants_not_classes"
require_relative "app/no_anonymous_class_in_spec"
require_relative "app/no_update_in_before"
require_relative "rbs/lint/no_untyped"
require_relative "rbs/style/no_compact_namespace"
