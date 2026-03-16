require "net/http"
require "json"

class GistUploader
  GITHUB_API = "https://api.github.com"

  class ApiError < StandardError; end

  def initialize(token:, gist_id: nil, filename:)
    @token    = token
    @gist_id  = gist_id
    @filename = filename
  end

  def self.from_env(filename:)
    new(token: ENV.fetch("GITHUB_TOKEN"), gist_id: ENV["GIST_ID"], filename: filename)
  end

  def upload(content)
    body = { files: { @filename => { content: content } } }

    if @gist_id
      request(:patch, "/gists/#{@gist_id}", body)["html_url"]
    else
      request(:post, "/gists", body.merge(description: "Job interviews tracker", public: false))["html_url"]
    end
  end

  private

  def request(method, path, body)
    uri  = URI("#{GITHUB_API}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    klass = method == :post ? Net::HTTP::Post : Net::HTTP::Patch
    req   = klass.new(uri)
    req["Authorization"] = "Bearer #{@token}"
    req["Accept"]        = "application/vnd.github+json"
    req["Content-Type"]  = "application/json"
    req.body             = JSON.generate(body)

    res  = http.request(req)
    data = JSON.parse(res.body)

    raise ApiError, "#{res.code} #{data['message']}" unless res.is_a?(Net::HTTPSuccess)

    data
  end
end
