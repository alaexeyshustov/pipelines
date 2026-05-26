# frozen_string_literal: true

module Evaluation
  module Improvement
    class ListExperimentsTool < ::RubyLLM::Tool
      description "List all completed experiments for an agent ordered by date. Use this to understand the direction of past improvement attempts before generating a revision."

      param :prompt_name, type: :string, desc: "Name of the agent whose experiment history to list.", required: true
      param :current_experiment_id, type: :integer, desc: "ID of the current experiment to exclude from results.", required: true

      def name = "list_experiments"

      def execute(prompt_name:, current_experiment_id:)
        experiments = load_experiments(prompt_name, current_experiment_id).to_a
        return [] if experiments.empty?

        metrics = load_metrics(prompt_name)
        averages_by_experiment = bulk_per_metric_averages(experiments)

        experiments.map { |exp| format_experiment(exp, metrics, averages_by_experiment[exp.id] || {}) }
      end

      private

      def load_experiments(prompt_name, current_experiment_id)
        Experiment
          .joins(:prompt)
          .where(status: :completed, evaluation_prompts: { name: prompt_name })
          .where.not(id: current_experiment_id)
          .includes(:prompt)
          .order(:created_at)
      end

      def load_metrics(prompt_name)
        Metric.where(agent_name: prompt_name, active: true).to_a
      end

      def bulk_per_metric_averages(experiments)
        results_table        = EvaluationResult.arel_table
        justifications_table = Justification.arel_table

        EvaluationResult
          .joins(
            results_table.join(justifications_table)
              .on(justifications_table[:evaluation_result_id].eq(results_table[:id]))
              .join_sources
          )
          .where(experiment: experiments)
          .group(results_table[:experiment_id], justifications_table[:metric_name])
          .average(results_table[:score])
          .each_with_object({} #: Hash[Integer, Hash[String, untyped]]
                            ) do |((exp_id, metric_name), avg), memo|
            memo[exp_id.to_i] ||= ({} #: Hash[String, untyped])
            memo[exp_id.to_i][metric_name.to_s] = avg
          end
      end

      def format_experiment(experiment, metrics, averages)
        {
          experiment_id: experiment.id,
          date: experiment.created_at.to_date.to_s,
          prompt_version: experiment.prompt&.version || 0,
          per_metric_averages: averages,
          overall_average: weighted_average(averages, metrics)
        }
      end

      def weighted_average(averages, metrics)
        return 0.0 if metrics.empty? || averages.empty?

        weighted_sum = 0.0
        total_weight = 0.0

        metrics.each do |metric|
          score = averages[metric.name.to_s]
          next if score.nil?

          weighted_sum += score.to_f * metric.weight.to_f
          total_weight += metric.weight.to_f
        end

        return 0.0 if total_weight.zero?

        (weighted_sum / total_weight).round(2).to_f
      end
    end
  end
end
