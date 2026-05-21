# frozen_string_literal: true

class Setting < ApplicationRecord
  KEYS = %w[emails_agent_model records_agent_model evaluation_llm_model judge_llm_model].freeze

  validates :key,   presence: true, uniqueness: true
  validates :value, presence: true

  def self.fetch(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value
    record.save!
  end
end
