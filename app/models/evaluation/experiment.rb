module Evaluation
  class Experiment < ApplicationRecord
    include AASM

    self.table_name = "evaluation_experiments"

    belongs_to :dataset, class_name: "Evaluation::Dataset"
    belongs_to :prompt, class_name: "Evaluation::Prompt", optional: true
    has_many :samples, class_name: "Evaluation::Sample", dependent: :destroy
    has_many :evaluation_results, through: :samples, class_name: "Evaluation::EvaluationResult"

    validates :name, :dataset, :evaluator_classes, presence: true

    serialize :evaluator_classes, coder: JSON, type: Array
    serialize :metadata, coder: JSON

    aasm column: :status do
      state :pending, initial: true
      state :sampling
      state :evaluating
      state :completed
      state :failed

      event :start_sampling do
        transitions from: :pending, to: :sampling
      end

      event :start_evaluating do
        transitions from: :sampling, to: :evaluating
      end

      event :complete do
        transitions from: :evaluating, to: :completed
      end

      event :fail do
        transitions from: %i[pending sampling evaluating], to: :failed
      end
    end

    def agent_name
      prompt&.name
    end

    def runner_model
      meta = metadata || {}
      agent = agent_name ? Orchestration::Agent.find_by(name: agent_name) : nil
      meta["pipeline_model"].presence || agent&.model.presence
    end

    def newer_experiment
      return unless prompt

      Experiment
        .joins(:prompt)
        .where(evaluation_prompts: { name: prompt.name })
        .where("evaluation_experiments.id > ?", id)
        .order(id: :desc)
        .includes(:prompt)
        .first
    end

    def per_metric_averages
      EvaluationResult.per_metric_averages(self)
    end
  end
end
