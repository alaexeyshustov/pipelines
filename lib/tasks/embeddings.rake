namespace :embeddings do
  desc "Embed every Email and Document (ADR 0014); with a model name, embed under it, switch the configured " \
       "embedding model to it and drop the old vectors (e.g. rake embeddings:reembed[bge-m3]). Unchanged content is skipped."
  task :reembed, [ :model ] => :environment do |_, args|
    model = args[:model].presence || LlmModels.embedding
    embedded = 0
    [ Email, Document ].each do |klass|
      klass.find_in_batches(batch_size: 32) { |records| embedded += Embeddings::Embed.call(records, model:).embedded }
    end
    Setting.set("embedding_model", model)
    Embedding.purge_except!(model)
    puts "Embedded #{embedded} records with #{model}."
  end
end
