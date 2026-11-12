require "rails_helper"

RSpec.describe Emails::Adapters::GmailAdapter, "#inbox_message_ids_after" do
  include GmailHelpers

  subject(:adapter) do
    described_class.from_env(credentials_path: GmailHelpers::CREDENTIALS_PATH, token_path: GmailHelpers.token_path)
  end

  let(:json) { { "Content-Type" => "application/json" } }

  before { setup_gmail }
  after  { teardown_gmail }

  it "lists INBOX messages from the given day, following page tokens" do
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/messages")
      .with(query: hash_including("labelIds" => "INBOX", "q" => "after:2026/01/05"))
      .to_return({ status: 200, headers: json, body: { messages: [ { id: "a" } ], nextPageToken: "p2" }.to_json })
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/messages")
      .with(query: hash_including("pageToken" => "p2"))
      .to_return({ status: 200, headers: json, body: { messages: [ { id: "b" } ] }.to_json })

    expect(adapter.inbox_message_ids_after(Date.new(2026, 1, 5))).to eq(%w[a b])
  end
end
