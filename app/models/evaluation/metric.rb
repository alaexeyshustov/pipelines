module Evaluation
  class Metric < ApplicationRecord
    self.table_name = "evaluation_metrics"

    # probability: yes/no (levels optional: {"yes" => ..., "no" => ...}); score: ordered level descriptions
    # (Array, >= 2); choice: {option => {"description" => ..., "value" => 0.0..1.0}} (or "pass" => true).
    KINDS = %w[probability score choice].freeze

    validates :agent_name, presence: true
    validates :name, presence: true, uniqueness: { scope: :agent_name }
    validates :description, presence: true
    validates :weight, presence: true, numericality: true
    validates :kind, inclusion: { in: KINDS }
    validates :minimum, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }, allow_nil: true
    validate :levels_match_kind

    scope :for_agent, ->(agent_name) { where(agent_name: agent_name) }
    scope :active, -> { where(active: true) }
    scope :active_for_agent, ->(agent_name) { active.for_agent(agent_name) }

    private

    def levels_match_kind
      case kind
      when "score" then errors.add(:levels, "must be an array of at least 2 descriptions") unless valid_score_levels?
      when "choice" then errors.add(:levels, "must define at least 2 options with values 0.0..1.0") unless valid_choice_levels?
      end
    end

    def valid_score_levels?
      levels.is_a?(Array) && levels.size >= 2 && levels.all?(&:present?)
    end

    def valid_choice_levels?
      return false unless levels.is_a?(Hash) && levels.size >= 2

      levels.values.all? do |option|
        option.is_a?(Hash) && (option["value"].nil? || (0.0..1.0).cover?(option["value"]))
      end
    end
  end
end
