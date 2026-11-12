require "rails_helper"

RSpec.describe Tags::Classifier do
  subject(:result) { described_class.call(item) }

  let(:item) { create(:email, subject: "Interview invite", from_address: "hr@acme.com", body: "Please pick a slot.") }
  let!(:job) { create(:tag, name: "job_application") }
  let!(:finance) { create(:tag, name: "finance") }
  let!(:rejection) { create(:subtag, tag: job, name: "rejection") }
  let(:probabilities) { { "job_application" => 0.9, "finance" => 0.2 } }
  let(:choices) { { "job_application" => "interview_invite" } }
  let(:bodies) { [] }

  before do
    create(:subtag, tag: job, name: "interview_invite")
    stub_request(:post, "https://api.openai.com/v1/decisions").to_return do |request|
      body = JSON.parse(request.body)
      bodies << body
      answers = body["questions"].map { |question| answer_for(question) }
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { model: "gpt-6-luna", answers: answers, usage: { input_tokens: 10, output_tokens: 2 } }.to_json }
    end
  end

  def option_names(question)
    question.fetch("choices", question["options"]).map { |o| o.is_a?(Hash) ? (o["name"] || o["value"]) : o }
  end

  def answer_for(question)
    if question["type"] == "predicate"
      { "probability" => probabilities.fetch(question["name"]) }
    else
      pick = choices.fetch(question["name"])
      { "choice" => pick, "confidence" => 0.8, "probabilities" => option_names(question).map { |name| { "value" => name, "probability" => name == pick ? 0.7 : 0.3 } } }
    end
  end

  it "assigns every tag at or above the threshold with its probability as confidence, and a subtag" do
    expect(result.taggings.map { |t| [ t.tag.name, t.subtag&.name, t.source, t.confidence ] })
      .to eq([ [ "job_application", "interview_invite", "llm", 0.9 ] ])
    expect(item.taggings.count).to eq(1)
  end

  it "assigns several tags and skips the subtag call for tags without subtags" do
    probabilities["finance"] = 0.35
    expect(result.taggings.map { |t| t.tag.name }).to contain_exactly("job_application", "finance")
    expect(bodies.size).to eq(2) # one multi-label call + one choice call (finance has no subtags)
    expect(item.taggings.find_by(tag: finance).subtag).to be_nil
  end

  it "leaves the subtag empty when the judge picks none of the options" do
    choices["job_application"] = described_class::NO_SUBTAG
    expect(result.taggings.map { |t| [ t.tag.name, t.subtag ] }).to eq([ [ "job_application", nil ] ])
  end

  it "offers a none option next to the subtags" do
    result
    expect(option_names(bodies.last["questions"].first)).to include(described_class::NO_SUBTAG, "interview_invite", "rejection")
  end

  it "asks the subtag questions of all kept tags in one call" do
    create(:subtag, tag: finance, name: "bank")
    probabilities["finance"] = 0.9
    choices["finance"] = "bank"
    expect(result.taggings.map { |t| [ t.tag.name, t.subtag&.name ] })
      .to contain_exactly([ "job_application", "interview_invite" ], [ "finance", "bank" ])
    expect(bodies.size).to eq(2)
  end

  it "leaves the item untagged when no tag reaches the threshold" do
    probabilities["job_application"] = 0.34
    expect(result.taggings).to be_empty
    expect(item.taggings).to be_empty
    expect(bodies.size).to eq(1)
  end

  it "honours a configured threshold" do
    Setting.set("tagging_threshold", "0.95")
    expect(result.taggings).to be_empty
  end

  it "sends the email subject, sender and body to the judge" do
    result
    expect(bodies.first["input"].to_s).to include("Interview invite", "hr@acme.com", "Please pick a slot.")
  end

  it "truncates long text" do
    item.update!(body: "x" * 50_000)
    result
    expect(bodies.first["input"].to_s.size).to be < 10_000
  end

  it "classifies documents from title and text" do
    document = create(:document, title: "Lease.pdf", text: "monthly rent")
    described_class.call(document)
    expect(bodies.first["input"].to_s).to include("Lease.pdf", "monthly rent")
    expect(document.taggings.pluck(:source)).to eq([ "llm" ])
  end

  it "replaces earlier llm taggings on re-tagging" do
    create(:tagging, taggable: item, tag: finance, source: "llm", confidence: 0.9)
    result
    expect(item.taggings.reload.map { |t| t.tag.name }).to eq([ "job_application" ])
  end

  it "never touches manual taggings and skips the llm write for that tag" do
    manual = create(:tagging, taggable: item, tag: job, subtag: rejection, source: "manual")
    other = create(:tagging, taggable: item, tag: finance, source: "manual")
    probabilities["finance"] = 0.9
    expect(result.taggings).to be_empty
    expect(item.taggings.reload).to contain_exactly(manual, other)
    expect(manual.reload.subtag).to eq(rejection)
  end

  it "lets provider errors propagate and keeps the previous llm taggings" do
    old = create(:tagging, taggable: item, tag: finance, source: "llm", confidence: 0.9)
    stub_request(:post, "https://api.openai.com/v1/decisions").to_return(status: 500, body: "{}")
    expect { result }.to raise_error(RubyLLM::Error)
    expect(item.taggings.reload).to contain_exactly(old)
  end

  it "does nothing when there are no tags" do
    Tagging.delete_all
    Subtag.delete_all
    Tag.delete_all
    expect(result.taggings).to be_empty
    expect(bodies).to be_empty
  end
end
