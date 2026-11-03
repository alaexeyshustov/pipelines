require "rails_helper"

RSpec.describe Email::YahooIdRewriter do
  describe ".rewrite" do
    it "rewrites bare Yahoo UIDs to <uid_validity>:<uid>" do
      create(:email, provider: "yahoo", provider_message_id: "101")
      create(:email, provider: "yahoo", provider_message_id: "102")

      expect(described_class.rewrite(777)).to eq(2)
      expect(Email.where(provider: "yahoo").pluck(:provider_message_id)).to contain_exactly("777:101", "777:102")
    end

    it "leaves already migrated ids and Gmail ids alone, so it is idempotent" do
      create(:email, provider: "yahoo", provider_message_id: "555:7")
      create(:email, provider: "gmail", provider_message_id: "18c3f")
      create(:email, provider: "yahoo", provider_message_id: "101")

      described_class.rewrite(777)

      expect(described_class.rewrite(777)).to eq(0)
      expect(Email.pluck(:provider, :provider_message_id)).to contain_exactly(
        [ "yahoo", "555:7" ], [ "gmail", "18c3f" ], [ "yahoo", "777:101" ]
      )
    end

    it "skips a row whose target id already exists" do
      create(:email, provider: "yahoo", provider_message_id: "777:101")
      create(:email, provider: "yahoo", provider_message_id: "101")

      expect(described_class.rewrite(777)).to eq(0)
      expect(Email.where(provider: "yahoo").count).to eq(2)
    end
  end

  describe ".rewrite_from_env" do
    it "uses the current INBOX UIDVALIDITY of the configured Yahoo account" do
      imap = Net::IMAP.allocate
      allow(Net::IMAP).to receive(:new).and_return(imap)
      allow(imap).to receive_messages(login: nil, logout: nil, disconnect: nil, status: { "UIDVALIDITY" => 888 })
      allow(Emails::Adapters::YahooAdapter).to receive(:from_env)
        .and_return(Emails::Adapters::YahooAdapter.new(host: "h", port: 993, username: "u", password: "p"))
      create(:email, provider: "yahoo", provider_message_id: "101")

      expect(described_class.rewrite_from_env).to eq(1)
      expect(Email.pick(:provider_message_id)).to eq("888:101")
    end

    it "does nothing without Yahoo credentials" do
      allow(Emails::Adapters::YahooAdapter).to receive(:from_env).and_raise(RuntimeError, "Missing Yahoo credentials")
      create(:email, provider: "yahoo", provider_message_id: "101")

      expect(described_class.rewrite_from_env).to be_nil
      expect(Email.pick(:provider_message_id)).to eq("101")
    end
  end
end
