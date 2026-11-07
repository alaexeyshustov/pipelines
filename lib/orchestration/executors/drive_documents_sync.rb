module Orchestration
  module Executors
    # Pipeline step: full scan of the whitelisted Drive folders (see Document::SyncDriveJob). Runs inline so the
    # step run records the outcome; returns the job's created/updated/unchanged/deleted/failed counts.
    class DriveDocumentsSync
      include Orchestration::Executable

      def self.call(**_kwargs)
        Document::SyncDriveJob.perform_now
      end
    end
  end
end
