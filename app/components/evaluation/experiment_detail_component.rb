module Evaluation
  class ExperimentDetailComponent < ViewComponent::Base
    renders_one :header, UI::PageHeaderComponent
    renders_one :status_badge, -> { Evaluation::Experiments::StatusBadgeComponent.new(experiment: @experiment) }
    renders_many :metric_rows, ->(metric:, avg:) { Evaluation::ExperimentMetricRowComponent.new(metric: metric, avg: avg, experiment: @experiment) }

    def initialize(experiment:)
      @experiment = experiment
    end

    def before_render
      setup_header
      with_status_badge
      setup_metric_rows
    end

    private

    def setup_header
      with_header(title: @experiment.name, parent: { label: "Experiments", url: helpers.evaluation_experiments_path }) do |h|
        unless @experiment.newer_experiment
          h.with_action(type: :button, label: "Improve Prompt", url: helpers.improve_evaluation_experiment_path(@experiment), method: :post, variant: :primary)
        end
        if @experiment.newer_experiment&.completed?
          h.with_action(type: :link, label: "View Comparison", url: helpers.compare_evaluation_experiment_path(@experiment, candidate_id: @experiment.newer_experiment.id), variant: :success)
        end
      end
    end

    def setup_metric_rows
      per_metric_avg_map = per_metric_avg
      metrics.each { |m| with_metric_row(metric: m, avg: per_metric_avg_map[m.name]) }
    end

    public

    def metrics
      @metrics ||= @experiment.agent_name ? Metric.for_agent(@experiment.agent_name).order(:name) : Evaluation::Metric.none
    end

    def sample_count
      @sample_count ||= @experiment.samples.count
    end

    def per_metric_avg
      @per_metric_avg ||= @experiment.per_metric_averages
    end

    def overall_avg
      return unless per_metric_avg.any?

      per_metric_avg.values.sum / per_metric_avg.size
    end

    def dataset_samples
      @dataset_samples ||= @experiment.dataset.dataset_samples
    end

    def judge_model
      @judge_model ||= Evaluators::LLMJudgeEval.judge_model
    end

    def output_schema_json
      JSON.pretty_generate(@experiment.prompt.output_schema)
    end
  end
end
