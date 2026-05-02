module Evaluation
  module AutoEvalTriggerable
    extend ActiveSupport::Concern

    included do
      after_create_commit { |record| Evaluation::PromptAutoEvalJob.perform_later(record.id) }
    end
  end
end
