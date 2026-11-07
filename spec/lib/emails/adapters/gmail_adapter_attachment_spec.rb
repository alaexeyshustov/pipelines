require "rails_helper"

RSpec.describe Emails::Adapters::GmailAdapter, "#attachment" do
  include GmailHelpers

  subject(:adapter) do
    described_class.from_env(credentials_path: GmailHelpers::CREDENTIALS_PATH, token_path: GmailHelpers.token_path)
  end

  before { setup_gmail }
  after  { teardown_gmail }

  it "returns the decoded attachment bytes" do
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/messages/msg1/attachments/att1")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { size: 5, data: Base64.urlsafe_encode64("%PDF-") }.to_json)

    expect(adapter.attachment("msg1", "att1")).to eq("%PDF-")
  end
end
