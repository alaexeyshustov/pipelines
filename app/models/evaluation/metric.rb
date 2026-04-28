module Evaluation
  class Metric < ApplicationRecord
    self.table_name = "evaluation_metrics"

    validates :agent_name, presence: true
    validates :name, presence: true, uniqueness: { scope: :agent_name }
    validates :description, presence: true
    validates :weight, presence: true, numericality: true

    scope :for_agent, ->(agent_name) { where(agent_name: agent_name) }
    scope :active, -> { where(active: true) }
  end
end
