module Evaluation
  class Prompt < ApplicationRecord
    self.table_name = "evaluation_prompts"

    include Evaluation::AutoEvalTriggerable

    has_many :experiments, class_name: "Evaluation::Experiment", foreign_key: :prompt_id, dependent: :nullify
    has_many :samples, class_name: "Evaluation::Sample", foreign_key: :prompt_id, dependent: :nullify

    validates :name, presence: true
    validates :user_prompt, presence: true

    before_validation :assign_next_version, on: :create

    def self.last_for_agent(agent_name)
      where(name: agent_name).order(version: :desc, id: :desc).first
    end

    private

    def assign_next_version
      return if version.present?

      self.version = self.class.where(name: name).maximum(:version).to_i + 1
    end
  end
end
