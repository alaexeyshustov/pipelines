module Interviews
  class GistExportService
    Result = Data.define(:ok, :message)
    class Result
      def ok? = ok
    end

    def self.call(ids:) = new(ids:).call

    def initialize(ids:)
      @ids = ids
    end

    def call
      token   = ENV["GITHUB_TOKEN"]
      gist_id = ENV["GIST_ID"]
      return Result.new(ok: false, message: "GITHUB_TOKEN is not configured.") if token.blank?
      return Result.new(ok: false, message: "GIST_ID is not configured.") if gist_id.blank?

      csv_content = Interviews::CsvExportService.call(ids: @ids).csv
      GistUploader.call(csv_content, token:, gist_id:, filename: "interviews.csv")
      Result.new(ok: true, message: "Interviews exported to gist #{gist_id}.")
    rescue GistUploader::ApiError => e
      Result.new(ok: false, message: e.message)
    end
  end
end
