
module Evaluation
  class WizardDraftCleanupJob < ApplicationJob
    queue_as :default

    def perform
      deleted = Evaluation::WizardDraft.cleanup_expired
      logger.info("[WizardDraftCleanupJob] Deleted #{deleted} expired drafts")
    end
  end
end
