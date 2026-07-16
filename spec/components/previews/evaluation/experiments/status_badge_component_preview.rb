
module Evaluation
  module Experiments
    class StatusBadgeComponentPreview < ViewComponent::Preview
      %w[pending sampling evaluating completed failed].each do |state|
        define_method(state) do
          experiment = Evaluation::Experiment.new(id: 1, name: "Experiment",
                                                  status: state,
                                                  dataset: Evaluation::Dataset.new(id: 1, name: "Demo"))
          render(Evaluation::Experiments::StatusBadgeComponent.new(experiment: experiment, with_src: false))
        end
      end
    end
  end
end
