require "net/http"
require "json"

class GistUploader
  GITHUB_API = "https://api.github.com"
  API_VERSION = "2022-11-28"
  GIST_ID_FORMAT = /\A[a-f0-9]{1,64}\z/i

  Result = Data.define(:url)

  class ApiError < StandardError; end
  class InvalidGistId < ApiError; end

  def self.call(content, token:, gist_id: nil, filename:) = new(token:, gist_id:, filename:).call(content)

  def initialize(token:, gist_id: nil, filename:)
    @token    = token
    @gist_id  = gist_id.presence
    @filename = filename
    validate_id
  end

  def self.from_env(filename:)
    new(token: ENV.fetch("GITHUB_TOKEN"), gist_id: ENV["GIST_ID"], filename: filename)
  end

  def call(content)
    body = { files: { @filename => { content: content } } }
    response =
      if @gist_id
        ensure_secret!
        request(:patch, "/gists/#{@gist_id}", body)
      else
        request(:post, "/gists", body.merge(description: "Job interviews tracker", public: false))
      end

    html_url = response["html_url"]
    Result.new(url: html_url&.to_s)
  end

  private

  def validate_id
    id = @gist_id
    return if id.nil? || GIST_ID_FORMAT.match?(id)

    raise InvalidGistId, "Invalid gist ID"
  end

  def ensure_secret!
    raise ApiError, "Refusing to update public gist" if request(:get, "/gists/#{@gist_id}")["public"] == true
  end

  def request(method, path, body = nil)
    uri  = URI("#{GITHUB_API}#{path}")
    http = build_http_client(uri)
    req  = build_http_request(method, uri, body)

    res  = http.request(req)
    data = parse_body(res)
    raise ApiError, "Unexpected GitHub response payload" unless data.is_a?(Hash)
    raise ApiError, "#{res.code} #{data['message']}" unless res.is_a?(Net::HTTPSuccess)

    data
  end

  def parse_body(res)
    JSON.parse(res.body.to_s)
  rescue JSON::ParserError
    raise ApiError, "GitHub API error (#{res.code})"
  end

  def build_http_client(uri)
    http         = Net::HTTP.new(uri.hostname.to_s, uri.port)
    http.use_ssl = true
    http
  end

  def build_http_request(method, uri, body)
    klass                  = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method)
    req                    = klass.new(uri)
    req["Authorization"]   = "Bearer #{@token}"
    req["Accept"]          = "application/vnd.github+json"
    req["X-GitHub-Api-Version"] = API_VERSION
    req["Content-Type"]    = "application/json"
    req.body               = JSON.generate(body) if body
    req
  end
end
