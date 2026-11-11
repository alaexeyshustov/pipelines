module Embeddings
  # Turns text into vectors with the configured embedding model (LlmModels.embedding, served by Ollama; ADR 0014).
  # Documents are embedded as is; Qwen3 needs a task instruction on the query side only, which RubyLLM does not add.
  module Client
    DIMENSIONS = 1024
    QUERY_INSTRUCTION = "Given a search query, retrieve relevant emails and documents".freeze

    module_function

    # One vector per text, from a single request.
    def documents(texts, model: LlmModels.embedding)
      return [] if texts.empty?

      RubyLLM.embed(texts, model:, provider: :ollama, assume_model_exists: true, dimensions: DIMENSIONS).vectors
    end

    def query(text, model: LlmModels.embedding)
      documents([ "Instruct: #{QUERY_INSTRUCTION}\nQuery: #{text}" ], model:).first
    end
  end
end
