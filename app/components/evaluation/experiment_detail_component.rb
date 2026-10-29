module Evaluation
  class ExperimentDetailComponent < ViewComponent::Base
    renders_one :header, UI::PageHeaderComponent
    renders_one :status_badge, -> { Evaluation::Experiments::StatusBadgeComponent.new(experiment: @experiment) }
    renders_many :metric_rows, ->(metric:, avg:) {
      Evaluation::ExperimentMetricRowComponent.new(metric: metric, avg: avg, experiment: @experiment, pass_rate: @metric_pass_rates[metric.name])
    }

    # usage: Evaluation::ExperimentUsageQuery::Usage; pass_rate / metric_pass_rates: Evaluation::PassRateQuery (callers load them).
    def initialize(experiment:, usage: nil, pass_rate: nil, metric_pass_rates: {})
      @experiment = experiment
      @usage = usage
      @pass_rate = pass_rate
      @metric_pass_rates = metric_pass_rates
    end

    def before_render
      setup_header
      with_status_badge
      setup_metric_rows
    end

    private

    def metric_weights
      @metric_weights ||= metrics.to_h { |m| [ m.name, m.weight.to_f ] }
    end

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

    # Weighted grade (0.0..1.0): metric averages weighted by Metric#weight, like Evaluation::SampleGrade.
    def overall_avg
      graded = per_metric_avg.slice(*metric_weights.keys)
      return if graded.empty?

      total = graded.keys.sum { |name| metric_weights.fetch(name) }
      graded.sum { |name, avg| avg * metric_weights.fetch(name) } / total unless total.zero?
    end

    def overall_label = ScoreFormatter.percent(overall_avg, digits: 1)
    def pass_rate_label = @pass_rate && ScoreFormatter.percent(@pass_rate, digits: 1)

    def usage?
      !@usage.nil? && @usage.calls.positive?
    end

    def cost_label = ScoreFormatter.cost(@usage&.cost)

    def tokens_label
      usage = @usage
      return unless usage

      "#{ScoreFormatter.tokens(usage.input_tokens)} in / #{ScoreFormatter.tokens(usage.output_tokens)} out"
    end

    def models_label = @usage&.models&.keys&.join(", ")

    def active_run?
      @experiment.pending? || @experiment.running?
    end

    def progress_label
      return unless @experiment.running?

      "#{sample_count} sampled, #{@experiment.pending_samples_count} pending"
    end

    def newer_experiment_active?
      newer = @experiment.newer_experiment
      !!newer && (newer.pending? || newer.running?)
    end

    def dataset_samples
      @dataset_samples ||= @experiment.dataset.dataset_samples
    end

    def judge_model
      @judge_model ||= @experiment.evaluation_model.presence || LlmModels.judge
    end

    def output_schema_json
      JSON.pretty_generate(@experiment.prompt.output_schema)
    end
  end
end
