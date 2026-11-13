# Helpers for specs that need vectors without a model: unit vectors and a stubbed Ollama embeddings endpoint.
module EmbeddingHelpers
  # The Ollama base specs configure (spec/support/ruby_llm.rb): unroutable by default, the real one in ollama mode.
  OLLAMA_EMBEDDINGS_URL = "#{LlmTestBackend.api_base.delete_suffix('/')}/embeddings".freeze

  # A 1024-dimensional vector with a single 1.0 at +index+ (unit vectors at different indexes are orthogonal).
  def unit_vector(index) = Array.new(Embeddings::Client::DIMENSIONS) { |i| i == index ? 1.0 : 0.0 }

  # Every embeddings request answers with +vector+ for each input text.
  def stub_ollama_embeddings(vector)
    stub_request(:post, OLLAMA_EMBEDDINGS_URL).to_return do |request|
      inputs = JSON.parse(request.body).fetch("input")
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { data: inputs.map { { embedding: vector } } }.to_json }
    end
  end

  def embed_as(record, vector, model: LlmModels.embedding)
    Embedding.store!(record, model:, content_digest: "digest", vector:)
  end
end
