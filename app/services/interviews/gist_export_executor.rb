module Interviews
  class GistExportExecutor
    include Orchestration::Executable

    input_schema(
      gist_id: { "type" => "string" }
    )

    def self.call(gist_id: nil, **)
      resolved_id = gist_id || ENV.fetch("GIST_ID", nil)
      return { "skipped" => true, "reason" => "GIST_ID not configured" } if resolved_id.nil?

      result = GistExportService.new(ids: nil, gist_id: resolved_id).call
      { "ok" => result.ok, "message" => result.message }
    end
  end
end
