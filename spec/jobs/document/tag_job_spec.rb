require "rails_helper"

RSpec.describe Document::TagJob do
  include ActiveJob::TestHelper

  let(:document) { create(:document) }

  def classified(status, error: nil) = Tags::Classify::Result.new(status:, error:)

  describe "#perform" do
    context "when the service classifies the document" do
      before { allow(Tags::Classify).to receive(:call).and_return(classified("tagged")) }

      it "delegates to Tags::Classify without forcing" do
        described_class.perform_now(document.id)

        expect(Tags::Classify).to have_received(:call).with(document, force: false)
      end

      it "passes force: through to reclassify an already classified document" do
        described_class.perform_now(document.id, force: true)

        expect(Tags::Classify).to have_received(:call).with(document, force: true)
      end
    end

    context "with the real service" do
      before do
        allow(Tags::Classifier).to receive(:call) do |item|
          Tagging.create!(taggable: item, tag: create(:tag), source: "llm", confidence: 0.9)
          Tags::Classifier::Result.new(taggings: [])
        end
      end

      it "marks a pending document tagged" do
        described_class.perform_now(document.id)

        expect(document.reload).to be_tagged
      end

      it "makes no LLM call for an already classified document, so a queued duplicate is a no-op" do
        document.update!(classification_status: "untagged")

        described_class.perform_now(document.id)

        expect(Tags::Classifier).not_to have_received(:call)
      end

      it "reclassifies an already classified document with force: true" do
        document.update!(classification_status: "untagged")

        described_class.perform_now(document.id, force: true)

        expect(document.reload).to be_tagged
      end
    end

    context "when the classifier raises a RubyLLM::Error" do
      before { allow(Tags::Classifier).to receive(:call).and_raise(RubyLLM::Error, "overloaded") }

      it "does not raise, so the job is not retried" do
        expect { described_class.perform_now(document.id) }.not_to raise_error
      end

      it "marks the document failed" do
        described_class.perform_now(document.id)

        expect(document.reload).to be_failed
      end
    end

    context "when the classifier raises a transport error" do
      before { allow(Tags::Classifier).to receive(:call).and_raise(RubyLLM::ConnectionError, "reset") }

      it "retries once and leaves the document failed" do
        perform_enqueued_jobs(only: described_class) { described_class.perform_later(document.id) }

        expect(Tags::Classifier).to have_received(:call).twice
        expect(document.reload).to be_failed
      end
    end

    it "ignores a Document that was deleted meanwhile" do
      expect { described_class.perform_now(0) }.not_to raise_error
    end
  end
end
