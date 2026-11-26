require "rails_helper"

RSpec.describe Orchestration::Executors::EmailsEmbed do
  include EmbeddingHelpers

  let(:embed_calls) { [] }
  let(:embed_outcome) { ->(_records) { Embeddings::Embed::Result.new(embedded: 1, unchanged: 0, skipped: 0) } }

  before do
    allow(Orchestration::Heartbeat).to receive(:beat)
    allow(Embeddings::Embed).to receive(:call) do |records, **|
      embed_calls << records
      embed_outcome.call(records)
    end
  end

  def execute(*emails) = described_class.call(email_ids: emails.map(&:id))

  it "embeds tagged emails without an embedding, one model call per record, and lists them as embedded" do
    first = create(:email, classification_status: "tagged")
    second = create(:email, classification_status: "tagged")

    output = execute(first, second)

    expect(output).to eq("embedded" => [ first.id, second.id ], "skipped" => [], "failed" => [])
    expect(embed_calls).to contain_exactly([ first ], [ second ])
  end

  %w[pending untagged failed].each do |status|
    it "skips a #{status} email without embedding it" do
      email = create(:email, classification_status: status)

      output = execute(email)

      expect(output).to include("embedded" => [], "skipped" => [ email.id ])
      expect(embed_calls).to be_empty
    end
  end

  it "does not embed a tagged email that already has an embedding for the current model" do
    email = create(:email, classification_status: "tagged")
    embed_as(email, unit_vector(0))

    output = execute(email)

    expect(output["embedded"]).to be_empty
    expect(embed_calls).to be_empty
  end

  it "embeds a tagged email whose only embedding is for another model" do
    email = create(:email, classification_status: "tagged")
    embed_as(email, unit_vector(0), model: "some-old-model")

    expect(execute(email)["embedded"]).to eq([ email.id ])
  end

  it "lists a tagged email without embeddable text as skipped" do
    email = create(:email, classification_status: "tagged", subject: nil, body: nil)
    allow(Embeddings::Embed).to receive(:call).and_return(Embeddings::Embed::Result.new(embedded: 0, unchanged: 0, skipped: 1))

    output = execute(email)

    expect(output).to include("embedded" => [], "skipped" => [ email.id ])
  end

  context "when the model call fails for one email" do
    let(:embed_outcome) do
      lambda do |records|
        raise RubyLLM::ConnectionError, "ollama down" if records.first.subject == "broken"

        Embeddings::Embed::Result.new(embedded: 1, unchanged: 0, skipped: 0)
      end
    end

    it "records it as failed with the error and embeds the rest" do
      broken = create(:email, classification_status: "tagged", subject: "broken")
      fine = create(:email, classification_status: "tagged")

      output = execute(broken, fine)

      expect(output["embedded"]).to eq([ fine.id ])
      expect(output["failed"]).to contain_exactly("id" => broken.id, "error" => a_string_including("ConnectionError", "ollama down"))
    end
  end

  it "handles an id once even when it is repeated" do
    email = create(:email, classification_status: "tagged")

    output = described_class.call(email_ids: [ email.id, email.id ])

    expect(output["embedded"]).to eq([ email.id ])
    expect(embed_calls.size).to eq(1)
  end

  it "beats the heartbeat per record" do
    emails = create_list(:email, 2, classification_status: "tagged")

    execute(*emails)

    expect(Orchestration::Heartbeat).to have_received(:beat).at_least(:twice)
  end

  it "declares email_ids as its required input and embedded, skipped and failed as outputs" do
    expect(described_class.input_schema["required"]).to eq([ "email_ids" ])
    expect(described_class.output_schema["required"]).to contain_exactly("embedded", "skipped", "failed")
  end

  it "is registered as a pipeline service" do
    expect(Orchestration::ServiceRegistry.lookup("Orchestration::Executors::EmailsEmbed")).to eq(described_class)
  end
end
