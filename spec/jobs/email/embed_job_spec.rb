require "rails_helper"

RSpec.describe Email::EmbedJob do
  include ActiveJob::TestHelper

  let(:url) { EmbeddingHelpers::OLLAMA_EMBEDDINGS_URL }
  let(:email) { create(:email) }

  it "embeds the email" do
    stub_request(:post, url).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { data: [ { embedding: Array.new(1024) { 0.5 } } ] }.to_json
    )

    described_class.perform_now(email.id)

    expect(email.embeddings.count).to eq(1)
  end

  it "ignores an email deleted in the meantime" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it "retries once when the model server is unreachable, then gives up" do
    allow(Embeddings::Embed).to receive(:call).and_raise(Faraday::ConnectionFailed, "refused")

    perform_enqueued_jobs(only: described_class) { described_class.perform_later(email.id) }

    expect(Embeddings::Embed).to have_received(:call).twice
    expect(email.embeddings.count).to eq(0)
  end
end
