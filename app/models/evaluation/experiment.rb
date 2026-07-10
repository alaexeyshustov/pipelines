module Evaluation
  class Experiment < ApplicationRecord
    include AASM
    include SteepHacks

    self.table_name = "evaluation_experiments"

    belongs_to :dataset, class_name: "Evaluation::Dataset"
    belongs_to :prompt, class_name: "Evaluation::Prompt", optional: true
    has_many :samples, class_name: "Evaluation::Sample", dependent: :destroy
    has_many :evaluation_results, through: :samples, class_name: "Evaluation::EvaluationResult"

    validates :name, presence: true

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
        transitions from: :sampling, to: :evaluating, guard: :ready_to_evaluate?
      end

      event :complete do
        transitions from: :evaluating, to: :completed, guard: :evaluations_finished?
      end

      event :fail do
        transitions from: %i[pending sampling evaluating], to: :failed
      end
    end

    def in_progress?
      sampling? || evaluating?
    end

    def agent_name
      prompt&.name
    end

    def runner_model
      meta = metadata || empty_object
      agent = agent_name ? Orchestration::Agent.named(agent_name) : nil
      meta["pipeline_model"].presence || agent&.model.presence
    end

    def self.completed_for_prompt_name(name) = joins(:prompt).where(status: :completed, evaluation_prompts: { name: name })

    def self.sibling_for_prompt_name(name, excluding_id:) = joins(:prompt).where(evaluation_prompts: { name: name }).where.not(id: excluding_id)

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

    private

    def ready_to_evaluate?
      pending_samples_count.zero? && pending_evaluations_count.positive?
    end

    def evaluations_finished?
      pending_evaluations_count.zero?
    end
  end
end
