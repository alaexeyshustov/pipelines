# frozen_string_literal: true

module Evaluation
  module Experiments
    class StatusBadgeComponent < ViewComponent::Base
      def initialize(experiment:, with_src: true)
        @experiment = experiment
        @with_src   = with_src
      end

      def badge_variant
        case @experiment.status.to_sym
        when :completed then :success
        when :failed    then :danger
        else                 :warning
        end
      end

      def polling?
        !@experiment.completed? && !@experiment.failed?
      end

      def turbo_src
        helpers.status_frame_evaluation_experiment_path(@experiment) if @with_src
      end
    end
  end
end
