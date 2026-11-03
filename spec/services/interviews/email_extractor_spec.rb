require "rails_helper"

RSpec.describe Interviews::EmailExtractor do
  include RecordsAgentHelpers

  subject(:result) { described_class.call(email) }

  let(:email) do
    create(:email, subject: "Your application", from_address: "jobs@acme.com", body: "We received your application.",
                   date: Time.zone.local(2026, 5, 4, 10))
  end
  let(:extraction) { { "company" => "Acme", "job_title" => "Ruby Developer", "action" => "apply" } }
  let(:llm_requests) { [] }

  before do
    create(:tagging, taggable: email, tag: create(:tag, name: "job_application"))
    stub_request(:post, mistral_completions_url).to_return do |request|
      llm_requests << JSON.parse(request.body)
      stub_mistral_body(extraction)
    end
  end

  def stub_mistral_body(content)
    { status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: "cmpl-test", object: "chat.completion", model: "mistral-large-latest",
              choices: [ { index: 0, message: { role: "assistant", content: content.to_json }, finish_reason: "stop" } ],
              usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } }.to_json }
  end

  def another_email(extra = {})
    create(:email, { date: Time.zone.local(2026, 5, 10, 9) }.merge(extra)).tap do |other|
      create(:tagging, taggable: other, tag: Tag.find_by!(name: "job_application"))
    end
  end

  describe "a new application" do
    it "creates a pending_reply Interview applied on the email date and links the email" do
      expect(result.interview).to have_attributes(
        company: "Acme", job_title: "Ruby Developer", status: "pending_reply", applied_at: Date.new(2026, 5, 4)
      )
      expect(email.reload.interview).to eq(result.interview)
    end

    it "asks the LLM with the email content and the extraction schema" do
      result
      request = llm_requests.sole
      expect(request.dig("response_format", "json_schema", "schema", "properties").keys)
        .to contain_exactly("company", "job_title", "action")
      expect(request["messages"].pluck("content").join).to include("We received your application.", "jobs@acme.com")
    end
  end

  describe "status transitions" do
    let!(:interview) { create(:interview, company: "Acme", job_title: "Ruby Developer", status: "pending_reply", applied_at: Date.new(2026, 5, 1)) }

    it "moves to having_interviews and records the first interview date on an interview email" do
      extraction["action"] = "interview"
      expect(result.interview).to eq(interview)
      expect(interview.reload).to have_attributes(status: "having_interviews", first_interview_at: Date.new(2026, 5, 4))
    end

    it "fills the next free interview slot" do
      interview.update!(status: "having_interviews", first_interview_at: Date.new(2026, 5, 2))
      extraction["action"] = "interview"
      result
      expect(interview.reload).to have_attributes(first_interview_at: Date.new(2026, 5, 2), second_interview_at: Date.new(2026, 5, 4))
    end

    it "does not record an interview date twice" do
      interview.update!(status: "having_interviews", first_interview_at: Date.new(2026, 5, 4))
      extraction["action"] = "interview"
      result
      expect(interview.reload.second_interview_at).to be_nil
    end

    it "marks a rejection with its date" do
      extraction["action"] = "rejection"
      result
      expect(interview.reload).to have_attributes(status: "rejected", rejected_at: Date.new(2026, 5, 4))
    end

    it "marks an offer" do
      extraction["action"] = "offer"
      result
      expect(interview.reload.status).to eq("offer_received")
    end

    it "leaves the status alone on a notification" do
      interview.update!(status: "having_interviews")
      extraction["action"] = "notification"
      result
      expect(interview.reload.status).to eq("having_interviews")
    end

    it "does not move the status back on a late application confirmation" do
      interview.update!(status: "rejected")
      result
      expect(interview.reload.status).to eq("rejected")
    end

    it "keeps the earliest applied_at" do
      expect { result }.not_to(change { interview.reload.applied_at })
    end

    it "takes applied_at from an earlier application email" do
      interview.update!(applied_at: Date.new(2026, 5, 9))
      expect { result }.to change { interview.reload.applied_at }.to(Date.new(2026, 5, 4))
    end

    it "falls back to the email date for applied_at when it is missing" do
      interview.update!(applied_at: nil)
      extraction["action"] = "interview"
      result
      expect(interview.reload.applied_at).to eq(Date.new(2026, 5, 4))
    end
  end

  describe "matching" do
    it "matches company and job title case-insensitively, ignoring surrounding whitespace" do
      existing = create(:interview, company: "ACME", job_title: "ruby developer")
      expect(result.interview).to eq(existing)
      expect(Interview.count).to eq(1)
    end

    it "keeps different job titles at one company apart" do
      create(:interview, company: "Acme", job_title: "Python Developer")
      expect { result }.to change(Interview, :count).by(1)
    end

    it "links several emails of one application to the same Interview" do
      first = result.interview
      extraction["action"] = "interview"
      second = described_class.call(another_email)
      expect(second.interview).to eq(first)
      expect(first.emails.count).to eq(2)
    end
  end

  describe "idempotency" do
    it "creates no duplicate and does not call the LLM again when the email is processed twice" do
      described_class.call(email)
      expect { described_class.call(email.reload) }.not_to change(Interview, :count)
      expect(llm_requests.size).to eq(1)
    end

    it "gives the same Interview back on a re-run" do
      expect(described_class.call(email).interview).to eq(described_class.call(email.reload).interview)
    end

    it "does not shift interview dates when the same interview email is re-processed from scratch" do
      extraction["action"] = "interview"
      described_class.call(email)
      email.update!(interview_id: nil)
      described_class.call(email)
      expect(Interview.sole).to have_attributes(first_interview_at: Date.new(2026, 5, 4), second_interview_at: nil)
    end
  end

  describe "emails that are not job applications" do
    it "ignores an email without the job_application tag" do
      other = create(:email)
      create(:tagging, taggable: other, tag: create(:tag, name: "finance"))
      expect(described_class.call(other).interview).to be_nil
      expect(Interview.count).to eq(0)
      expect(llm_requests).to be_empty
    end

    it "creates nothing when the LLM finds no company or job title" do
      extraction.merge!("company" => "", "job_title" => "")
      expect(result.interview).to be_nil
      expect(Interview.count).to eq(0)
      expect(email.reload.interview_id).to be_nil
    end
  end

  describe "provider errors" do
    it "propagates a RubyLLM::Error and writes nothing" do
      stub_request(:post, mistral_completions_url).to_return(status: 500, body: { error: { message: "boom" } }.to_json)
      expect { result }.to raise_error(RubyLLM::Error)
      expect(Interview.count).to eq(0)
      expect(email.reload.interview_id).to be_nil
    end
  end
end
