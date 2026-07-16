
class Setting < ApplicationRecord
  KEYS = %w[emails_agent_model records_agent_model evaluation_llm_model judge_llm_model].freeze

  validates :key,   presence: true, uniqueness: true
  validates :value, presence: true

  def self.fetch(key)
    Rails.cache.fetch(cache_key(key)) { find_by(key: key)&.value }
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value
    record.save!
    Rails.cache.write(cache_key(key), value)
  end

  def self.cache_key(key)
    "setting/#{key}"
  end
  private_class_method :cache_key
end
