require 'rails_helper'

RSpec.describe GistUploader do
  let(:token)    { 'ghp_test_token' }
  let(:filename) { 'interviews.md' }
  let(:content)  { '# My Interviews' }
  let(:html_url) { 'https://gist.github.com/abc123' }

  describe '.from_env' do
    it 'builds an instance from GITHUB_TOKEN and GIST_ID env vars' do
      allow(ENV).to receive(:fetch).with('GITHUB_TOKEN').and_return(token)
      allow(ENV).to receive(:[]).with('GIST_ID').and_return('gist_42')

      uploader = described_class.from_env(filename: filename)
      expect(uploader).to be_a(described_class)
    end

    it 'raises KeyError when GITHUB_TOKEN is absent' do
      allow(ENV).to receive(:fetch).with('GITHUB_TOKEN').and_raise(KeyError)
      expect { described_class.from_env(filename: filename) }.to raise_error(KeyError)
    end
  end

  describe '#upload' do
    context 'when gist_id is provided (update)' do
      subject(:uploader) { described_class.new(token: token, gist_id: 'gist_42', filename: filename) }

      before do
        stub_request(:patch, "https://api.github.com/gists/gist_42")
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
        expect(uploader.upload(content)).to eq(html_url)
      end

      it 'sends the file content in the request body' do
        uploader.upload(content)
        expect(WebMock).to have_requested(:patch, "https://api.github.com/gists/gist_42")
          .with(body: hash_including('files' => { filename => { 'content' => content } }))
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
        expect(uploader.upload(content)).to eq(html_url)
      end

      it 'includes description and public: false in the request body' do
        uploader.upload(content)
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
        expect { uploader.upload(content) }
          .to raise_error(GistUploader::ApiError, /401.*Bad credentials/)
      end
    end
  end
end
