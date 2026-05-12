# frozen_string_literal: true

module Evaluation
  class SyntheticDatasetGenerator
    def self.call(draft_token:, agent_name:, dataset_name:, count:, hints: nil)
      SyntheticDatasetJob.perform_later(
        draft_token:  draft_token,
        agent_name:   agent_name,
        dataset_name: dataset_name,
        count:        count.to_i.clamp(1, 50),
        hints:        hints.to_s
      )
      draft_token
    end
  end
end
