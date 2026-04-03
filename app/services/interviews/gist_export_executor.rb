module Interviews
  class GistExportExecutor
    include Orchestration::Executable

    def self.call(input, _params = {})
      gist_id = input.fetch("gist_id") { ENV.fetch("GIST_ID", nil) }
      return { "skipped" => true, "reason" => "GIST_ID not configured" } if gist_id.nil?

      result = GistExportService.new(ids: nil, gist_id: gist_id).call
      { "ok" => result.ok, "message" => result.message }
    end
  end
end
