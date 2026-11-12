require "rails_helper"

RSpec.describe Embeddings::Text do
  describe ".for" do
    it "joins an email's subject and body" do
      email = build(:email, subject: "Interview invite", body: "See you on Monday.")
      expect(described_class.for(email)).to eq("Interview invite\n\nSee you on Monday.")
    end

    it "falls back to the text of the HTML body" do
      email = build(:email, subject: "Offer", body: nil, html_body: "<style>p{}</style><p>Welcome&nbsp;aboard</p><p>Start&amp;go</p>")
      expect(described_class.for(email)).to eq("Offer\n\nWelcome aboard\nStart&go")
    end

    it "drops quoted replies and the signature" do
      body = "Thanks, confirmed.\n> On Monday you wrote:\n> older text\n\nBest\n-- \nJane Doe\nACME Corp"
      expect(described_class.for(build(:email, subject: "Re: plan", body:))).to eq("Re: plan\n\nThanks, confirmed.\n\nBest")
    end

    it "joins a document's title and text" do
      document = build(:document, title: "Lease.pdf", text: "# Lease\n\nRent is due monthly.")
      expect(described_class.for(document)).to eq("Lease.pdf\n\n# Lease\n\nRent is due monthly.")
    end

    it "is empty for a record without any content" do
      expect(described_class.for(build(:email, subject: nil, body: nil, html_body: nil))).to eq("")
    end

    it "truncates long content to the character budget" do
      document = build(:document, title: "Long", text: "ä" * (described_class::MAX_CHARS * 2))
      expect(described_class.for(document).length).to eq(described_class::MAX_CHARS)
    end
  end
end
