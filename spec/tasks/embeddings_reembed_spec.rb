require "rails_helper"
require "rake"

RSpec.describe "embeddings:reembed" do # rubocop:disable RSpec/DescribeClass
  include EmbeddingHelpers
  include RakeTaskHelpers

  let(:task) { Rake::Task["embeddings:reembed"] }
  let!(:email) { create(:email) }
  let!(:document) { create(:document) }
  let!(:other_email) { create(:email) }

  before do
    load_rake_task("embeddings:reembed")
    Setting.set("embedding_model", "old-model")
    [ email, document, other_email ].each { |record| embed_as(record, unit_vector(0), model: "old-model") }
    stub_ollama_embeddings(unit_vector(1))
  end

  def run(*args) = expect { task.invoke(*args) }.to output.to_stdout

  context "with a new model" do
    before { run("new-model") }

    it "embeds every email and document under the new model batching each kind into one request" do
      expect(Embedding.where(model: "new-model").map(&:embeddable)).to contain_exactly(email, other_email, document)
      expect(a_request(:post, EmbeddingHelpers::OLLAMA_EMBEDDINGS_URL).with(body: hash_including("model" => "new-model"))).to have_been_made.twice
    end

    it "switches the configured model and drops the old embeddings and vectors" do
      expect(LlmModels.embedding).to eq("new-model")
      expect(Embedding.distinct.pluck(:model)).to eq([ "new-model" ])
      expect(Embedding.connection.select_values("SELECT model FROM embedding_vectors").uniq).to eq([ "new-model" ])
    end

    it "makes searches use the new vectors" do
      expect(Email.semantic_search("anything").map(&:embeddable)).to contain_exactly(email, other_email)
    end
  end

  context "without an argument" do
    it "embeds what is missing under the configured model and leaves unchanged content alone" do
      embed_as(email, unit_vector(0), model: "old-model").update!(content_digest: Digest::SHA256.hexdigest(Embeddings::Text.for(email)))
      run

      expect(a_request(:post, EmbeddingHelpers::OLLAMA_EMBEDDINGS_URL).with(body: hash_including("input" => [ Embeddings::Text.for(document) ]))).to have_been_made.once
      expect(LlmModels.embedding).to eq("old-model")
    end
  end

  context "when the model server fails" do
    it "keeps the old embeddings and the configured model" do
      stub_request(:post, EmbeddingHelpers::OLLAMA_EMBEDDINGS_URL).to_return(status: 500, body: "boom")

      expect { task.invoke("new-model") }.to raise_error(RubyLLM::Error)

      expect(Embedding.distinct.pluck(:model)).to eq([ "old-model" ])
      expect(LlmModels.embedding).to eq("old-model")
    end
  end
end
