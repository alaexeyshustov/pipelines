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
      return Result.new(ok: false, message: "GITHUB_TOKEN is not configured.") if token.nil? || token.empty?

      csv_content = Interviews::CsvExportService.new(ids: @ids).call
      response    = patch_gist(token, csv_content)

      if response.is_a?(Net::HTTPSuccess)
        Result.new(ok: true, message: "Interviews exported to gist #{@gist_id}.")
      else
        body = parse_error_body(response.body)
        message = body&.[]("message")
        if message.is_a?(String) && !message.empty?
          Result.new(ok: false, message: message.to_s)
        else
          Result.new(ok: false, message: "GitHub API error (#{response.code}).")
        end
      end
    end

    private

    def parse_error_body(body)
      parsed = JSON.parse(body)
      parsed.is_a?(Hash) ? parsed.transform_keys(&:to_s) : nil
    rescue JSON::ParserError
      nil
    end

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
