# frozen_string_literal: true

require "net/http"
require "json"

module Interviews
  class GistExportService
    GITHUB_API_URI = "https://api.github.com"

    Result = Data.define(:ok, :message)
    class Result
      def ok? = ok
    end

    def initialize(ids:, gist_id:)
      @ids     = ids
      @gist_id = gist_id
    end

    def call
      return Result.new(ok: false, message: "Gist ID is required.") if @gist_id.blank?

      token = ENV["GITHUB_TOKEN"]
      return Result.new(ok: false, message: "GITHUB_TOKEN is not configured.") if token.blank?

      csv_content = Interviews::CsvExportService.new(ids: @ids).call
      response    = patch_gist(token, csv_content)

      if response.is_a?(Net::HTTPSuccess)
        Result.new(ok: true, message: "Interviews exported to gist #{@gist_id}.")
      else
        body    = JSON.parse(response.body) rescue {} # : Hash[String, untyped]
        message = body["message"] || "GitHub API error (#{response.code})."
        Result.new(ok: false, message: message)
      end
    end

    private

    def patch_gist(token, csv_content)
      uri  = URI("#{GITHUB_API_URI}/gists/#{@gist_id}")
      http = Net::HTTP.new(uri.hostname.to_s, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Patch.new(uri)
      request["Authorization"]  = "Bearer #{token}"
      request["Accept"]         = "application/vnd.github+json"
      request["X-GitHub-Api-Version"] = "2022-11-28"
      request["Content-Type"]   = "application/json"
      request.body = JSON.generate(
        files: { "interviews.csv" => { content: csv_content } }
      )

      http.request(request)
    end
  end
end
