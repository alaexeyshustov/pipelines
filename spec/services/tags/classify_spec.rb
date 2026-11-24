require "rails_helper"

RSpec.describe Tags::Classify do
  subject(:result) { described_class.call(item) }

  let(:item) { create(:email, classification_status: status, subject: "Interview invite", body: "Please pick a slot.") }
  let(:status) { "pending" }
  let!(:job_tag) { create(:tag, name: "job_application") }
  let!(:finance) { create(:tag, name: "finance") }
  let(:probabilities) { { "job_application" => 0.9, "finance" => 0.2 } }

  # The real classifier, with the judge's decisions endpoint stubbed (as in classifier_spec).
  before do
    stub_request(:post, "https://api.openai.com/v1/decisions").to_return do |request|
      answers = JSON.parse(request.body).fetch("questions").map do |question|
        { "name" => question["name"], "probability" => probabilities.fetch(question["name"]) }
      end
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { model: "gpt-6-luna", answers: answers, usage: { input_tokens: 10, output_tokens: 2 } }.to_json }
    end
  end

  def status_of(result) = result.status.to_s

  describe "records that need classifying" do
    %w[pending failed].each do |starting_status|
      context "when the status is #{starting_status}" do
        let(:status) { starting_status }

        it "classifies the item and marks it tagged when it got a tagging", :aggregate_failures do
          expect(status_of(result)).to eq("tagged")
          expect(result.error).to be_nil
          expect(item.reload).to be_tagged
          expect(item.taggings.sole).to have_attributes(tag: job_tag, source: "llm")
        end
      end
    end

    it "marks the item untagged when the classifier assigned nothing" do
      probabilities["job_application"] = 0.1

      expect(status_of(result)).to eq("untagged")
      expect(item.reload).to be_untagged
    end

    it "classifies a Document too" do
      document = create(:document, classification_status: "pending")

      expect(status_of(described_class.call(document))).to eq("tagged")
      expect(document.reload).to be_tagged
    end

    it "marks an item with only manual taggings tagged, even when the classifier adds none" do
      create(:tagging, taggable: item, tag: finance, source: "manual")
      probabilities["job_application"] = 0.1

      expect(status_of(result)).to eq("tagged")
      expect(item.reload).to be_tagged
    end
  end

  describe "records that are already classified" do
    %w[tagged untagged].each do |done|
      context "when the status is #{done}" do
        let(:status) { done }

        it "skips them without calling the classifier", :aggregate_failures do
          allow(Tags::Classifier).to receive(:call).and_call_original

          expect(status_of(result)).to eq("skipped")
          expect(Tags::Classifier).not_to have_received(:call)
          expect(item.reload.classification_status).to eq(done)
          expect(a_request(:post, "https://api.openai.com/v1/decisions")).not_to have_been_made
        end

        it "classifies them again with force: true" do
          expect(status_of(described_class.call(item, force: true))).to eq("tagged")
          expect(item.reload).to be_tagged
        end
      end
    end

    it "force: true replaces only llm taggings" do
      item.update!(classification_status: "tagged")
      create(:tagging, taggable: item, tag: finance, source: "llm", confidence: 0.99)
      create(:tagging, taggable: item, tag: job_tag, source: "manual")
      probabilities.delete("job_application")

      described_class.call(item, force: true)

      expect(item.taggings.reload.map { |t| [ t.tag.name, t.source ] }).to eq([ %w[job_application manual] ])
    end
  end

  describe "errors" do
    before { allow(Tags::Classifier).to receive(:call).and_raise(error) }

    context "when the provider rejects the call (a RubyLLM::Error)" do
      let(:error) { RubyLLM::Error.new("overloaded") }

      it "marks the item failed and returns the message, without raising" do
        expect(status_of(result)).to eq("failed")
        expect(result.error).to include("overloaded")
        expect(item.reload).to be_failed
      end
    end

    [ RubyLLM::ConnectionError, Net::OpenTimeout, Net::ReadTimeout ].each do |klass|
      context "when the transport fails with #{klass}" do
        let(:error) { klass.new("reset") }

        it "marks the item failed and re-raises so the job's retry_on applies" do
          expect { result }.to raise_error(klass)
          expect(item.reload).to be_failed
        end
      end
    end
  end

  describe "the Result" do
    it "has status and error" do
      expect(described_class::Result.members).to eq(%i[status error])
    end
  end
end
