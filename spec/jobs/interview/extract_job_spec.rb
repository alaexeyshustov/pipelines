require "rails_helper"

RSpec.describe Interview::ExtractJob do
  include ActiveJob::TestHelper

  let(:email) { create(:email) }

  before { allow(Interviews::EmailExtractor).to receive(:call).and_return(Interviews::EmailExtractor::Result.new(interview: nil)) }

  it "extracts the interview from the email" do
    described_class.perform_now(email.id)
    expect(Interviews::EmailExtractor).to have_received(:call).with(email)
  end

  it "is queued on the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  context "when the extractor raises a RubyLLM::Error" do
    before { allow(Interviews::EmailExtractor).to receive(:call).and_raise(RubyLLM::Error, "overloaded") }

    it "retries, as the email already has tagged_at and nothing else would queue the extraction again" do
      perform_enqueued_jobs(only: described_class) { described_class.perform_later(email.id) }
      expect(Interviews::EmailExtractor).to have_received(:call).exactly(3).times
    end

    it "does not raise once retries are exhausted" do
      expect { perform_enqueued_jobs(only: described_class) { described_class.perform_later(email.id) } }.not_to raise_error
    end
  end

  context "when the extractor raises a transport error" do
    before { allow(Interviews::EmailExtractor).to receive(:call).and_raise(Faraday::ConnectionFailed, "reset") }

    it "retries once" do
      perform_enqueued_jobs(only: described_class) { described_class.perform_later(email.id) }
      expect(Interviews::EmailExtractor).to have_received(:call).twice
    end

    it "does not raise once retries are exhausted" do
      expect { perform_enqueued_jobs(only: described_class) { described_class.perform_later(email.id) } }.not_to raise_error
    end
  end
end
