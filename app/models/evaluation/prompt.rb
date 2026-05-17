module Evaluation
  class Prompt < ApplicationRecord
    self.table_name = "evaluation_prompts"

    include Evaluation::AutoEvalTriggerable

    has_many :experiments, class_name: "Evaluation::Experiment", foreign_key: :prompt_id, dependent: :nullify
    has_many :runner_results, class_name: "Evaluation::RunnerResult", foreign_key: :prompt_id, dependent: :nullify

    validates :name, presence: true
    validates :user_prompt, presence: true

    before_save :increment_version

    private

    def increment_version
      self.version = (version || 0) + 1
    end
  end
end
