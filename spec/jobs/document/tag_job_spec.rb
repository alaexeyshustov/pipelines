require "rails_helper"

RSpec.describe Document::TagJob do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:document) { create(:document) }

  describe "#perform" do
    context "when the classifier succeeds" do
      before { allow(Tags::Classifier).to receive(:call).and_return(Tags::Classifier::Result.new(taggings: [])) }

      it "classifies the document and sets tagged_at" do
        freeze_time do
          described_class.perform_now(document.id)
          expect(Tags::Classifier).to have_received(:call).with(document)
          expect(document.reload.tagged_at).to eq(Time.current)
        end
      end
    end

    context "when the document is already tagged" do
      let(:document) { create(:document, tagged_at: 1.day.ago) }

      before { allow(Tags::Classifier).to receive(:call) }

      it "makes no LLM call, so a queued duplicate is a no-op" do
        described_class.perform_now(document.id)
        expect(Tags::Classifier).not_to have_received(:call)
      end
    end

    context "when the classifier raises a RubyLLM::Error" do
      before { allow(Tags::Classifier).to receive(:call).and_raise(RubyLLM::Error, "overloaded") }

      it "does not raise, so the job is not retried" do
        expect { described_class.perform_now(document.id) }.not_to raise_error
      end

      it "leaves tagged_at nil" do
        described_class.perform_now(document.id)
        expect(document.reload.tagged_at).to be_nil
      end
    end

    context "when the classifier raises a transport error" do
      before { allow(Tags::Classifier).to receive(:call).and_raise(Faraday::ConnectionFailed, "reset") }

      it "retries once and leaves tagged_at nil" do
        perform_enqueued_jobs(only: described_class) { described_class.perform_later(document.id) }
        expect(Tags::Classifier).to have_received(:call).twice
        expect(document.reload.tagged_at).to be_nil
      end
    end

    it "ignores a Document that was deleted meanwhile" do
      expect { described_class.perform_now(0) }.not_to raise_error
    end
  end
end
