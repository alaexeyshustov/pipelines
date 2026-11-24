# Steps 2 and 5 of the Email Ingestion pipeline: classify the records of the ids they receive, filtering by status
# themselves. Parameters: the executor class, the factory, and the input key (:email_ids or :document_ids).
RSpec.shared_examples "a classify executor" do |factory:, key:|
  let(:outcomes) { {} }
  let(:ids_key) { key }

  before do
    allow(Orchestration::Heartbeat).to receive(:beat)
    allow(Tags::Classify).to receive(:call) { |item, **| outcomes.fetch(item.id) }
  end

  def classified(status, error: nil) = Tags::Classify::Result.new(status:, error:)

  def execute(*records) = described_class.call(ids_key => records.map(&:id))

  it "classifies pending and failed records and buckets the outcomes into tagged, untagged and failed" do
    tagged = create(factory, classification_status: "pending")
    untagged = create(factory, classification_status: "failed")
    broken = create(factory, classification_status: "pending")
    outcomes.merge!(tagged.id => classified("tagged"), untagged.id => classified("untagged"),
                    broken.id => classified("failed", error: "RubyLLM::Error: overloaded"))

    expect(execute(tagged, untagged, broken)).to eq(
      "tagged" => [ tagged.id ], "untagged" => [ untagged.id ],
      "failed" => [ { "id" => broken.id, "error" => "RubyLLM::Error: overloaded" } ]
    )
  end

  it "does not touch records that are already tagged or untagged" do
    done = [ create(factory, classification_status: "tagged"), create(factory, classification_status: "untagged") ]

    expect(execute(*done)).to eq("tagged" => [], "untagged" => [], "failed" => [])
    expect(Tags::Classify).not_to have_received(:call)
  end

  it "classifies each record once even when an id is repeated" do
    record = create(factory, classification_status: "pending")
    outcomes[record.id] = classified("tagged")

    output = described_class.call(key => [ record.id, record.id ])

    expect(output["tagged"]).to eq([ record.id ])
    expect(Tags::Classify).to have_received(:call).once
  end

  it "records an exception from one record as failed and goes on with the rest" do
    bad = create(factory, classification_status: "pending")
    good = create(factory, classification_status: "pending")
    allow(Tags::Classify).to receive(:call) do |item, **|
      item.id == bad.id ? raise(RubyLLM::ConnectionError, "reset") : classified("tagged")
    end

    output = execute(bad, good)

    expect(output["tagged"]).to eq([ good.id ])
    expect(output["failed"]).to contain_exactly("id" => bad.id, "error" => a_string_including("ConnectionError", "reset"))
  end

  it "beats the heartbeat once per classified record" do
    records = create_list(factory, 2, classification_status: "pending")
    records.each { |record| outcomes[record.id] = classified("tagged") }

    execute(*records)

    expect(Orchestration::Heartbeat).to have_received(:beat).at_least(:twice)
  end

  it "returns empty buckets for no ids" do
    expect(described_class.call(key => [])).to eq("tagged" => [], "untagged" => [], "failed" => [])
  end

  it "declares the id list as its only input, required" do
    schema = described_class.input_schema

    expect(schema["properties"].keys).to eq([ key.to_s ])
    expect(schema["properties"][key.to_s]).to include("type" => "array", "items" => include("type" => "integer"))
    expect(schema["required"]).to eq([ key.to_s ])
  end

  it "declares tagged, untagged and failed outputs, all required" do
    schema = described_class.output_schema

    expect(schema["required"]).to contain_exactly("tagged", "untagged", "failed")
    expect(schema["properties"]["tagged"]).to include("type" => "array", "items" => include("type" => "integer"))
    expect(schema["properties"]["failed"]).to include("type" => "array")
  end
end
