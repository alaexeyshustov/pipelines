require "rails_helper"

RSpec.describe Embeddings::Embed do
  let(:url) { "http://localhost:11434/v1/embeddings" }

  def vector(seed) = Array.new(Embeddings::Client::DIMENSIONS) { |i| i == seed ? 1.0 : 0.0 }

  # Answers every request with one vector per input text.
  def stub_ollama
    stub_request(:post, url).to_return do |request|
      inputs = JSON.parse(request.body).fetch("input")
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { data: inputs.each_index.map { |i| { embedding: vector(i) } } }.to_json }
    end
  end

  before { stub_ollama }

  it "embeds an email under the configured model with the digest of its text" do
    email = create(:email, subject: "Offer", body: "Welcome aboard")

    result = described_class.call([ email ])

    expect(result).to have_attributes(embedded: 1, unchanged: 0, skipped: 0)
    expect(email.embeddings.sole).to have_attributes(
      model: "qwen3-embedding:0.6b", dimensions: 1024, content_digest: Digest::SHA256.hexdigest("Offer\n\nWelcome aboard")
    )
    expect(a_request(:post, url).with(body: hash_including("input" => [ "Offer\n\nWelcome aboard" ]))).to have_been_made
  end

  it "embeds a document" do
    document = create(:document)
    described_class.call([ document ])
    expect(document.embeddings.count).to eq(1)
  end

  it "does not call the model again while the text is unchanged" do
    email = create(:email)
    described_class.call([ email ])

    result = described_class.call([ email ])

    expect(result).to have_attributes(embedded: 0, unchanged: 1)
    expect(a_request(:post, url)).to have_been_made.once
  end

  it "re-embeds when the text changed, keeping one embedding" do
    email = create(:email, body: "first")
    described_class.call([ email ])
    email.update!(body: "second")

    described_class.call([ email ])

    expect(email.embeddings.sole.content_digest).to eq(Digest::SHA256.hexdigest("#{email.subject}\n\nsecond"))
    expect(a_request(:post, url)).to have_been_made.twice
  end

  it "embeds a batch in one request and leaves out the unchanged ones" do
    done = create(:email)
    described_class.call([ done ])
    WebMock.reset_executed_requests!
    fresh = [ create(:email), create(:document) ]

    result = described_class.call([ done, *fresh ])

    expect(result).to have_attributes(embedded: 2, unchanged: 1)
    expect(a_request(:post, url)).to have_been_made.once
    expect(fresh.map { |record| record.embeddings.count }).to eq([ 1, 1 ])
  end

  it "skips records without any text" do
    email = create(:email, subject: nil, body: nil)
    expect(described_class.call([ email ])).to have_attributes(embedded: 0, skipped: 1)
    expect(a_request(:post, url)).not_to have_been_made
  end

  it "embeds under another model when asked, next to the existing one" do
    email = create(:email)
    described_class.call([ email ])
    described_class.call([ email ], model: "bge-m3")
    expect(email.embeddings.pluck(:model)).to contain_exactly("qwen3-embedding:0.6b", "bge-m3")
    expect(a_request(:post, url).with(body: hash_including("model" => "bge-m3"))).to have_been_made
  end
end
