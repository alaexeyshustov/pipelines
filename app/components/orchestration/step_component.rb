# frozen_string_literal: true

module Orchestration
  class StepComponent < ViewComponent::Base
    with_collection_parameter :step

    renders_many :detach_buttons, UI::DialogComponent
    renders_one :remove_button, UI::DialogComponent

    def initialize(step:, step_counter:, step_iteration:, pipeline:, actions:)
      @step = step
      @step_counter = step_counter
      @step_iteration = step_iteration
      @pipeline = pipeline
      @actions = actions
    end

    def before_render
      @step.step_actions.each do |sa|
        with_detach_button(
          label: "×",
          dialog_title: "Detach action \"#{sa.action.name}\"?",
          button_class: "ml-1 text-gray-400 hover:text-red-500 bg-transparent border-0 cursor-pointer p-0 font-bold"
        ) do |c|
          c.with_confirm_action do
            helpers.button_to(
              "Yes, detach",
              helpers.orchestration_pipeline_step_step_action_path(@pipeline, @step, sa),
              method: :delete,
              class: "px-4 py-2 text-sm text-white font-medium bg-red-600 rounded-lg hover:bg-red-700 cursor-pointer"
            )
          end
        end
      end

      with_remove_button(
        label: "Remove",
        dialog_title: "Remove step \"#{@step.name}\"?",
        button_class: "text-red-500 hover:text-red-700 bg-transparent border-0 cursor-pointer p-0 text-xs font-medium"
      ) do |c|
        c.with_confirm_action do
          helpers.button_to(
            "Yes, remove",
            helpers.orchestration_pipeline_step_path(@pipeline, @step),
            method: :delete,
            class: "px-4 py-2 text-sm text-white font-medium bg-red-600 rounded-lg hover:bg-red-700 cursor-pointer"
          )
        end
      end
    end

    def move_up?
      !@step_iteration.first?
    end

    def move_down?
      !@step_iteration.last?
    end

    def name_classes
      @step.enabled? ? "font-medium text-gray-900" : "font-medium text-gray-400"
    end

    def toggle_label
      @step.enabled? ? "Disable" : "Enable"
    end

    def toggle_button_classes
      base = "bg-transparent border rounded px-2 py-1 text-xs cursor-pointer transition-colors"
      color = @step.enabled? ? "text-gray-500 border-gray-200 hover:bg-gray-50" : "text-green-600 border-green-200 hover:bg-green-50"
      "#{base} #{color}"
    end

    def actions_select_options
      @actions.map { |a| [ a.name, a.id ] }
    end
  end
end
