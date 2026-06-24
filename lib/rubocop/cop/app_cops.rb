# frozen_string_literal: true

module RuboCop
  module Cop
    module AppCops
    end
  end
end

require_relative "app/service_must_have_class_call"
require_relative "app/service_must_have_instance_call"
require_relative "app/service_single_public_method"
require_relative "app/service_result_must_use_data_define"
require_relative "app/service_must_not_call_service"
require_relative "app/form_object_must_inherit_base_form"
require_relative "app/no_test_doubles"
require_relative "app/no_sleep_in_system_specs"
require_relative "app/aasm_must_specify_column"
require_relative "app/no_current_in_component"
require_relative "app/component_must_have_preview"
require_relative "app/no_all_each_in_job"
require_relative "app/no_html_building_in_helper"
require_relative "rbs/lint/no_untyped"
