module Orchestration
  module Executors
    class InterviewsGistExporter
      include Orchestration::Executable

      def self.call(**_kwargs)
        new.execute
      end

      def initialize(**_kwargs); end

      def execute
        return { "skipped" => true, "reason" => "GIST_ID not configured" } if ENV.fetch("GIST_ID", nil).blank?

        result = Interviews::GistExportService.call(ids: nil)
        { "ok" => result.ok, "message" => result.message }
      end
    end
  end
end
