# frozen_string_literal: true

module Evaluation
  module Improvement
    class ListExperimentsTool < ::RubyLLM::Tool
      description "List all completed experiments for an agent ordered by date. Use this to understand the direction of past improvement attempts before generating a revision."

      param :prompt_name, type: :string, desc: "Name of the agent whose experiment history to list.", required: true
      param :current_experiment_id, type: :integer, desc: "ID of the current experiment to exclude from results.", required: true

      def name = "list_experiments"

      def execute(prompt_name:, current_experiment_id:)
        experiments = load_experiments(prompt_name, current_experiment_id).to_a # : Array[Evaluation::Experiment]
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
          .includes(:prompt).order(:created_at) # : Evaluation::Experiment::relation
      end

      def load_metrics(prompt_name)
        Metric.where(agent_name: prompt_name, active: true).to_a # : Array[Evaluation::Metric]
      end

      def bulk_per_metric_averages(experiments)
        averages_for(experiments).each_with_object(Hash.new) { |(key, avg), memo| accumulate_metric(memo, key, avg) }
      end

      def accumulate_metric(memo, key, avg)
        exp_id, metric_name = key
        metric_averages = memo[exp_id]
        unless metric_averages
          metric_averages = Hash.new
          memo[exp_id] = metric_averages
        end
        metric_averages[metric_name] = avg
        metric_averages
      end

      def averages_for(experiments)
        EvaluationResult
          .joins(result_justification_join)
          .where(experiment: experiments)
          .group(EvaluationResult.arel_table[:experiment_id], Justification.arel_table[:metric_name])
          .average(EvaluationResult.arel_table[:score]) # : Hash[[Integer, String], Numeric?]
      end

      def result_justification_join
        results_table        = EvaluationResult.arel_table
        justifications_table = Justification.arel_table
        results_table
          .join(justifications_table)
          .on(justifications_table[:evaluation_result_id].eq(results_table[:id]))
          .join_sources
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

        weighted_sum, total_weight = accumulate_weights(averages, metrics)
        return 0.0 if total_weight.zero?

        (weighted_sum / total_weight).round(2).to_f
      end

      def accumulate_weights(averages, metrics)
        weighted_sum = 0.0
        total_weight = 0.0
        metrics.each do |metric|
          score = averages[metric.name.to_s]
          next if score.nil?

          weighted_sum += Float(score.to_s) * metric.weight.to_f
          total_weight += metric.weight.to_f
        end
        [ weighted_sum, total_weight ]
      end
    end
  end
end
