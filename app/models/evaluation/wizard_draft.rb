
module Evaluation
  class WizardDraft < ApplicationRecord
    include SteepHacks

    self.table_name = "evaluation_wizard_drafts"

    validates :session_token, presence: true, uniqueness: true
    validates :step, numericality: { only_integer: true }, inclusion: { in: 1..4 }

    def self.find_or_create_for_token(token)
      find_or_create_by!(session_token: token)
    end

    def self.cleanup_expired
      where(updated_at: ...24.hours.ago).delete_all
    end

    def advance!(new_step, payload_updates = empty_object)
      merged = (payload || empty_object).merge(payload_updates.stringify_keys)
      update!(step: new_step, payload: merged)
    end

    def merge_payload!(updates)
      merged = (payload || empty_object).merge(updates.stringify_keys)
      update!(payload: merged)
    end

    def payload_for_step(key)
      (payload || empty_object)[key.to_s]
    end
  end
end
