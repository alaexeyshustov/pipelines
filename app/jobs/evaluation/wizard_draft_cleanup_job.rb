# frozen_string_literal: true

module Evaluation
  class WizardDraftCleanupJob < ApplicationJob
    queue_as :default

    def perform
      deleted = Evaluation::WizardDraft.cleanup_expired
      Rails.logger.info("[WizardDraftCleanupJob] Deleted #{deleted} expired drafts")
    end
  end
end
