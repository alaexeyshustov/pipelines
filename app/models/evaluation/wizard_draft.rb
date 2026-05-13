# frozen_string_literal: true

module Evaluation
  class WizardDraft < ApplicationRecord
    self.table_name = "evaluation_wizard_drafts"

    validates :session_token, presence: true, uniqueness: true
    validates :step, numericality: { only_integer: true }, inclusion: { in: 1..4 }

    def self.find_or_create_for_token(token)
      find_or_create_by!(session_token: token)
    end

    def self.cleanup_expired
      where("updated_at < ?", 24.hours.ago).delete_all
    end

    # Merges updates into payload and advances the step.
    def advance!(new_step, payload_updates = {})
      merged = (payload || {}).merge(payload_updates.stringify_keys)
      update!(step: new_step, payload: merged)
    end

    # Merges updates into payload without changing the current step.
    def merge_payload!(updates)
      merged = (payload || {}).merge(updates.stringify_keys)
      update!(payload: merged)
    end

    def payload_for_step(key)
      (payload || {})[key.to_s]
    end
  end
end
