require 'rails_helper'

RSpec.describe GistUploader do
  let(:token)    { 'ghp_test_token' }
  let(:filename) { 'interviews.md' }
  let(:content)  { '# My Interviews' }
  let(:html_url) { 'https://gist.github.com/abc123' }

  describe '.from_env' do
    it 'builds an instance from GITHUB_TOKEN and GIST_ID env vars' do
      allow(ENV).to receive(:fetch).with('GITHUB_TOKEN').and_return(token)
      allow(ENV).to receive(:[]).with('GIST_ID').and_return('abc123')

      uploader = described_class.from_env(filename: filename)
      expect(uploader).to be_a(described_class)
    end

    it 'raises InvalidGistId when GIST_ID is not hex' do
      allow(ENV).to receive(:fetch).with('GITHUB_TOKEN').and_return(token)
      allow(ENV).to receive(:[]).with('GIST_ID').and_return('../user')

      expect { described_class.from_env(filename: filename) }.to raise_error(GistUploader::InvalidGistId)
    end

    it 'raises KeyError when GITHUB_TOKEN is absent' do
      allow(ENV).to receive(:fetch).with('GITHUB_TOKEN').and_raise(KeyError)
      expect { described_class.from_env(filename: filename) }.to raise_error(KeyError)
    end
  end

  describe '#call' do
    context 'when gist_id is provided (update)' do
      subject(:uploader) { described_class.new(token: token, gist_id: 'abc123', filename: filename) }

      before do
        stub_request(:get, "https://api.github.com/gists/abc123")
          .to_return(
            status: 200,
            body:   { public: false }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        stub_request(:patch, "https://api.github.com/gists/abc123")
          .with(
            headers: {
              'Authorization' => "Bearer #{token}",
              'Accept'        => 'application/vnd.github+json',
              'Content-Type'  => 'application/json'
            }
          )
          .to_return(
            status: 200,
            body:   { html_url: html_url }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'PATCHes the existing gist and returns html_url' do
        expect(uploader.call(content).url).to eq(html_url)
      end

      it 'sends the file content in the request body' do
        uploader.call(content)
        expect(WebMock).to have_requested(:patch, "https://api.github.com/gists/abc123")
          .with(body: hash_including('files' => { filename => { 'content' => content } }))
      end

      it 'checks the gist visibility with a GET before the PATCH' do
        uploader.call(content)
        expect(WebMock).to have_requested(:get, "https://api.github.com/gists/abc123")
          .with(headers: { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/vnd.github+json' })
        expect(WebMock).to have_requested(:patch, "https://api.github.com/gists/abc123").once
      end

      it 'sends the API version header on GET and PATCH' do
        uploader.call(content)
        expect(WebMock).to have_requested(:get, "https://api.github.com/gists/abc123")
          .with(headers: { 'X-GitHub-Api-Version' => '2022-11-28' })
        expect(WebMock).to have_requested(:patch, "https://api.github.com/gists/abc123")
          .with(headers: { 'X-GitHub-Api-Version' => '2022-11-28' })
      end
    end

    context 'when the visibility GET is sent' do
      subject(:uploader) { described_class.new(token: token, gist_id: 'abc123', filename: filename) }

      before do
        stub_request(:get, "https://api.github.com/gists/abc123")
          .to_return(status: 200, body: { public: false }.to_json)
        stub_request(:patch, "https://api.github.com/gists/abc123")
          .to_return(status: 200, body: { html_url: html_url }.to_json)
      end

      it 'carries no request body' do
        uploader.call(content)
        expect(WebMock).to(have_requested(:get, "https://api.github.com/gists/abc123")
          .with { |req| req.body.to_s.empty? })
      end
    end

    context 'when the gist is public' do
      subject(:uploader) { described_class.new(token: token, gist_id: 'abc123', filename: filename) }

      before do
        stub_request(:get, "https://api.github.com/gists/abc123")
          .to_return(status: 200, body: { public: true }.to_json)
      end

      it 'raises ApiError and never sends the PATCH' do
        expect { uploader.call(content) }
          .to raise_error(GistUploader::ApiError, 'Refusing to update public gist')
        expect(WebMock).not_to have_requested(:patch, "https://api.github.com/gists/abc123")
      end
    end

    context 'when an uppercase hex id is given' do
      subject(:uploader) { described_class.new(token: token, gist_id: 'ABC123', filename: filename) }

      before do
        stub_request(:get, "https://api.github.com/gists/ABC123")
          .to_return(status: 200, body: { public: false }.to_json)
        stub_request(:patch, "https://api.github.com/gists/ABC123")
          .to_return(status: 200, body: { html_url: html_url }.to_json)
      end

      it 'accepts it' do
        expect(uploader.call(content).url).to eq(html_url)
      end
    end

    context 'when gist_id is invalid' do
      [ '../user', "abc\n123", 'a' * 65, 'abcxyz', 'abc/123' ].each do |bad_id|
        it "raises InvalidGistId for #{bad_id.inspect} without any request" do
          expect { described_class.new(token: token, gist_id: bad_id, filename: filename) }
            .to raise_error(GistUploader::InvalidGistId)
          expect(WebMock).not_to have_requested(:any, /api\.github\.com/)
        end
      end

      it 'is an ApiError' do
        expect(GistUploader::InvalidGistId).to be < GistUploader::ApiError
      end

      it 'accepts a 64-char hex id' do
        expect { described_class.new(token: token, gist_id: 'a' * 64, filename: filename) }.not_to raise_error
      end
    end

    context 'when gist_id is an empty string (create)' do
      subject(:uploader) { described_class.new(token: token, gist_id: '', filename: filename) }

      before do
        stub_request(:post, "https://api.github.com/gists")
          .to_return(status: 201, body: { html_url: html_url }.to_json)
      end

      it 'POSTs a new gist' do
        expect(uploader.call(content).url).to eq(html_url)
        expect(WebMock).to have_requested(:post, "https://api.github.com/gists").once
      end
    end

    context 'when gist_id is absent (create)' do
      subject(:uploader) { described_class.new(token: token, gist_id: nil, filename: filename) }

      before do
        stub_request(:post, "https://api.github.com/gists")
          .to_return(
            status: 201,
            body:   { html_url: html_url }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'POSTs a new gist and returns html_url' do
        expect(uploader.call(content).url).to eq(html_url)
      end

      it 'sends the API version header and makes no GET' do
        uploader.call(content)
        expect(WebMock).to have_requested(:post, "https://api.github.com/gists")
          .with(headers: { 'X-GitHub-Api-Version' => '2022-11-28' })
        expect(WebMock).not_to have_requested(:get, /api\.github\.com/)
      end

      it 'includes description and public: false in the request body' do
        uploader.call(content)
        expect(WebMock).to have_requested(:post, "https://api.github.com/gists")
          .with(body: hash_including('description' => 'Job interviews tracker', 'public' => false))
      end
    end

    context 'when the API returns an error' do
      subject(:uploader) { described_class.new(token: token, gist_id: nil, filename: filename) }

      before do
        stub_request(:post, "https://api.github.com/gists")
          .to_return(
            status: 401,
            body:   { message: 'Bad credentials' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'raises ApiError with the status code and message' do
        expect { uploader.call(content) }
          .to raise_error(GistUploader::ApiError, /401.*Bad credentials/)
      end
    end

    context 'when the API returns a non-JSON error body' do
      subject(:uploader) { described_class.new(token: token, gist_id: 'abc123', filename: filename) }

      before do
        stub_request(:get, "https://api.github.com/gists/abc123")
          .to_return(status: 502, body: '<html>Bad Gateway</html>', headers: { 'Content-Type' => 'text/html' })
      end

      it 'raises ApiError with the status code' do
        expect { uploader.call(content) }
          .to raise_error(GistUploader::ApiError, 'GitHub API error (502)')
      end
    end
  end
end
