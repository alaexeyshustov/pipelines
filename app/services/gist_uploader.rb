require "net/http"
require "json"

class GistUploader
  GITHUB_API = "https://api.github.com"

  class ApiError < StandardError; end

  def self.call(content, token:, gist_id: nil, filename:) = new(token:, gist_id:, filename:).call(content)

  def initialize(token:, gist_id: nil, filename:)
    @token    = token
    @gist_id  = gist_id
    @filename = filename
  end

  def self.from_env(filename:)
    new(token: ENV.fetch("GITHUB_TOKEN"), gist_id: ENV["GIST_ID"], filename: filename)
  end

  def call(content)
    body = { files: { @filename => { content: content } } }
    response =
      if @gist_id
        request(:patch, "/gists/#{@gist_id}", body)
      else
        request(:post, "/gists", body.merge(description: "Job interviews tracker", public: false))
      end

    html_url = response["html_url"]
    html_url.nil? ? nil : html_url.to_s
  end

  private

  def request(method, path, body)
    uri  = URI("#{GITHUB_API}#{path}")
    http = build_http_client(uri)
    req  = build_http_request(method, uri, body)

    res  = http.request(req)
    data = JSON.parse(res.body)
    raise ApiError, "Unexpected GitHub response payload" unless data.is_a?(Hash)
    raise ApiError, "#{res.code} #{data['message']}" unless res.is_a?(Net::HTTPSuccess)

    data
  end

  def build_http_client(uri)
    http         = Net::HTTP.new(uri.hostname.to_s, uri.port)
    http.use_ssl = true
    http
  end

  def build_http_request(method, uri, body)
    klass                  = method == :post ? Net::HTTP::Post : Net::HTTP::Patch
    req                    = klass.new(uri)
    req["Authorization"]   = "Bearer #{@token}"
    req["Accept"]          = "application/vnd.github+json"
    req["Content-Type"]    = "application/json"
    req.body               = JSON.generate(body)
    req
  end
end
