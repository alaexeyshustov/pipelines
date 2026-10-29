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

    # Share of dataset samples that must be sampled and graded for a run to count as completed.
    COMPLETION_THRESHOLD = 0.8

    aasm column: :status do
      state :pending, initial: true
      state :running
      state :completed
      state :failed

      event :start do
        transitions from: :pending, to: :running
      end

      event :complete do
        transitions from: :running, to: :completed, guard: :run_finished_above_threshold?
      end

      event :fail do
        transitions from: %i[pending running], to: :failed
      end
    end

    def agent_name
      prompt&.name
    end

    def runner_model
      meta = metadata || empty_object
      agent = agent_name ? Orchestration::AgentCatalog.find(agent_name) : nil
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

    def run_finished_above_threshold?
      pending_samples_count.zero? && samples.count >= dataset.dataset_samples.count * COMPLETION_THRESHOLD
    end
  end
end
