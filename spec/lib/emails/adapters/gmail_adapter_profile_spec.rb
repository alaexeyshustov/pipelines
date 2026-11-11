require "rails_helper"

RSpec.describe Emails::Adapters::GmailAdapter, "#profile" do
  include GmailHelpers

  subject(:adapter) do
    described_class.from_env(credentials_path: GmailHelpers::CREDENTIALS_PATH, token_path: GmailHelpers.token_path)
  end

  let(:json) { { "Content-Type" => "application/json" } }

  before { setup_gmail }
  after  { teardown_gmail }

  it "returns the account address and the current historyId" do
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/profile")
      .to_return(status: 200, headers: json, body: { emailAddress: "me@gmail.com", historyId: "4242" }.to_json)

    expect(adapter.profile).to eq(email_address: "me@gmail.com", history_id: "4242")
  end

  it "is available through the Emails facade" do
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/profile")
      .to_return(status: 200, headers: json, body: { emailAddress: "me@gmail.com", historyId: "7" }.to_json)

    expect(Emails.profile("gmail")).to eq(email_address: "me@gmail.com", history_id: "7")
  end
end
