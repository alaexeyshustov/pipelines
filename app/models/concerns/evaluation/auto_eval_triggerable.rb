module Evaluation
  module AutoEvalTriggerable
    extend ActiveSupport::Concern

    included do
      after_create_commit { |record| Evaluation::PromptAutoEvalJob.perform_later(prompt_id: record.id) }
    end
  end
end
