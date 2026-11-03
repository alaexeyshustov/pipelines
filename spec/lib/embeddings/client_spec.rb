require "rails_helper"

RSpec.describe Embeddings::Client do
  let(:url) { "http://localhost:11434/v1/embeddings" }

  def vector(seed) = Array.new(described_class::DIMENSIONS) { |i| (seed + i) / 10_000.0 }

  def stub_ollama(*vectors)
    body = { data: vectors.map { |v| { embedding: v } }, usage: { prompt_tokens: 3 } }.to_json
    stub_request(:post, url).to_return(status: 200, body:, headers: { "Content-Type" => "application/json" })
  end

  describe ".documents" do
    it "returns one vector per text from a single request" do
      stub_ollama(vector(1), vector(2))
      expect(described_class.documents([ "first", "second" ])).to eq([ vector(1), vector(2) ])
      expect(a_request(:post, url)).to have_been_made.once
    end

    it "asks the configured model for 1024 dimensions without any instruction" do
      stub_ollama(vector(1))
      described_class.documents([ "plain text" ])
      expect(a_request(:post, url).with(body: hash_including(
        "model" => "qwen3-embedding:0.6b", "dimensions" => 1024, "input" => [ "plain text" ]
      ))).to have_been_made
    end

    it "makes no request for no texts" do
      expect(described_class.documents([])).to eq([])
      expect(a_request(:post, url)).not_to have_been_made
    end

    it "raises when the model returns another vector size" do
      stub_ollama(Array.new(768, 0.1))
      expect { described_class.documents([ "x" ]) }.to raise_error(Embeddings::Client::DimensionMismatch, /768/)
    end
  end

  describe ".query" do
    it "prefixes the Qwen3 retrieval instruction and returns a single vector" do
      stub_ollama(vector(5))
      expect(described_class.query("lease terms")).to eq(vector(5))
      expected = "Instruct: Given a search query, retrieve relevant emails and documents\nQuery: lease terms"
      expect(a_request(:post, url).with(body: hash_including("input" => [ expected ]))).to have_been_made
    end
  end
end
