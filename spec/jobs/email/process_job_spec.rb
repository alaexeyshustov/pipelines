require "rails_helper"

RSpec.describe Email::ProcessJob do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:email) { create(:email) }
  let!(:tag) { create(:tag, name: "job_application") }

  def classify_as_tagged
    allow(Tags::Classifier).to receive(:call) do |item|
      Tagging.create!(taggable: item, tag: tag, source: "llm")
      Tags::Classifier::Result.new(taggings: item.taggings.to_a)
    end
  end

  describe "#perform" do
    context "when the classifier tags the email" do
      before { classify_as_tagged }

      it "classifies the email" do
        described_class.perform_now(email.id)
        expect(Tags::Classifier).to have_received(:call).with(email)
      end

      it "sets tagged_at" do
        freeze_time do
          described_class.perform_now(email.id)
          expect(email.reload.tagged_at).to eq(Time.current)
        end
      end

      it "enqueues the attachment extraction" do
        expect { described_class.perform_now(email.id) }
          .to have_enqueued_job(Document::ExtractEmailAttachmentsJob).with(email.id)
      end
    end

    context "when the email carries the job_application tag" do
      before { classify_as_tagged }

      it "enqueues the interview extraction" do
        expect { described_class.perform_now(email.id) }
          .to have_enqueued_job(Interview::ExtractJob).with(email.id)
      end
    end

    context "when the email only has other tags" do
      before do
        other = create(:tag, name: "finance")
        allow(Tags::Classifier).to receive(:call) do |item|
          Tagging.create!(taggable: item, tag: other, source: "llm")
          Tags::Classifier::Result.new(taggings: item.taggings.to_a)
        end
      end

      it "enqueues no interview extraction" do
        expect { described_class.perform_now(email.id) }.not_to have_enqueued_job(Interview::ExtractJob)
      end
    end

    context "when the classifier assigns no tag" do
      before { allow(Tags::Classifier).to receive(:call).and_return(Tags::Classifier::Result.new(taggings: [])) }

      it "still sets tagged_at" do
        described_class.perform_now(email.id)
        expect(email.reload.tagged_at).not_to be_nil
      end

      it "enqueues no attachment extraction" do
        expect { described_class.perform_now(email.id) }.not_to have_enqueued_job(Document::ExtractEmailAttachmentsJob)
      end

      it "enqueues no interview extraction" do
        expect { described_class.perform_now(email.id) }.not_to have_enqueued_job(Interview::ExtractJob)
      end
    end

    context "when the email only has a manual tagging" do
      before do
        Tagging.create!(taggable: email, tag: tag, source: "manual")
        allow(Tags::Classifier).to receive(:call).and_return(Tags::Classifier::Result.new(taggings: []))
      end

      it "keeps the manual tagging" do
        described_class.perform_now(email.id)
        expect(email.taggings.pluck(:source)).to eq([ "manual" ])
      end

      it "enqueues the interview extraction for a manual job_application tag" do
        expect { described_class.perform_now(email.id) }
          .to have_enqueued_job(Interview::ExtractJob).with(email.id)
      end

      it "enqueues the attachment extraction for it" do
        expect { described_class.perform_now(email.id) }
          .to have_enqueued_job(Document::ExtractEmailAttachmentsJob).with(email.id)
      end
    end

    context "when the classifier raises a RubyLLM::Error" do
      before { allow(Tags::Classifier).to receive(:call).and_raise(RubyLLM::Error, "overloaded") }

      it "does not raise, so the job is not retried" do
        expect { described_class.perform_now(email.id) }.not_to raise_error
      end

      it "leaves tagged_at nil" do
        described_class.perform_now(email.id)
        expect(email.reload.tagged_at).to be_nil
      end

      it "enqueues nothing" do
        expect { described_class.perform_now(email.id) }.not_to have_enqueued_job
      end
    end

    context "when the classifier raises a transport error" do
      before { allow(Tags::Classifier).to receive(:call).and_raise(Faraday::ConnectionFailed, "reset") }

      it "retries once" do
        perform_enqueued_jobs(only: described_class) { described_class.perform_later(email.id) }
        expect(Tags::Classifier).to have_received(:call).twice
      end

      it "leaves tagged_at nil once retries are exhausted" do
        perform_enqueued_jobs(only: described_class) { described_class.perform_later(email.id) }
        expect(email.reload.tagged_at).to be_nil
      end
    end
  end
end
