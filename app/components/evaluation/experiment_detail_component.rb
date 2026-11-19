module Evaluation
  class ExperimentDetailComponent < ViewComponent::Base
    renders_one :header, UI::PageHeaderComponent
    renders_one :status_badge, -> { Evaluation::Experiments::StatusBadgeComponent.new(experiment: @experiment) }
    renders_many :metric_rows, ->(metric:, avg:) {
      Evaluation::ExperimentMetricRowComponent.new(metric: metric, avg: avg, experiment: @experiment, pass_rate: @metric_pass_rates[metric.name])
    }

    # metrics: the agent's Evaluation::Metric rows; usage: Evaluation::ExperimentUsageQuery::Usage;
    # pass_rate / metric_pass_rates: Evaluation::PassRateQuery (callers load them);
    # active_prompt: the live version of the agent (or an AgentDefaultPrompt), diffed against this experiment's prompt.
    def initialize(experiment:, metrics:, sample_count:, usage: nil, pass_rate: nil, metric_pass_rates: {}, active_prompt: nil)
      @experiment = experiment
      @metrics = metrics
      @sample_count = sample_count
      @usage = usage
      @pass_rate = pass_rate
      @metric_pass_rates = metric_pass_rates
      @active_prompt = active_prompt
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
        header_actions.each { |action| h.with_action(**action) }
      end
    end

    def header_actions = [ improve_action, activate_action, comparison_action ].compact

    def improve_action
      return if @experiment.newer_experiment

      { type: :button, label: "Improve Prompt", url: helpers.improve_evaluation_experiment_path(@experiment), method: :post, variant: :primary }
    end

    def activate_action
      return unless @experiment.completed? && @experiment.prompt && !prompt_active?

      { type: :button, label: "Activate", url: helpers.activate_evaluation_experiment_path(@experiment), method: :post, variant: :success }
    end

    def comparison_action
      newer = @experiment.newer_experiment
      return unless newer&.completed?

      { type: :link, label: "View Comparison", url: helpers.compare_evaluation_experiment_path(@experiment, candidate_id: newer.id), variant: :success }
    end

    def setup_metric_rows
      per_metric_avg_map = per_metric_avg
      metrics.each { |m| with_metric_row(metric: m, avg: per_metric_avg_map[m.name]) }
    end

    public

    attr_reader :metrics, :sample_count, :active_prompt

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

    def progress_label
      return unless @experiment.running?

      "#{sample_count} sampled, #{@experiment.pending_samples_count} pending"
    end

    def prompt_active? = !!@experiment.prompt&.active?

    # Only shown for a prompt that differs from what is live: the active version itself has nothing to diff.
    def active_prompt_diff? = !!@active_prompt && !!@experiment.prompt && !prompt_active?

    def newer_experiment_active?
      newer = @experiment.newer_experiment
      !!newer && (newer.pending? || newer.running?)
    end

    def dataset_samples
      @dataset_samples ||= @experiment.dataset.dataset_samples.to_a
    end

    def judge_model
      @judge_model ||= @experiment.evaluation_model.presence || LlmModels.judge
    end

    def output_schema_json
      JSON.pretty_generate(@experiment.prompt.output_schema)
    end
  end
end
