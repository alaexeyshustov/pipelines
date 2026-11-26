require "rails_helper"

RSpec.describe Emails::Adapters::GmailAdapter, "#inbox_message_ids_after" do
  include GmailHelpers

  subject(:adapter) do
    described_class.from_env
  end

  let(:json) { { "Content-Type" => "application/json" } }
  let(:from) { Time.utc(2026, 1, 5, 3, 30) }

  before { setup_gmail }
  after  { teardown_gmail }

  it "lists INBOX messages received since the epoch second, following page tokens" do
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/messages")
      .with(query: hash_including("labelIds" => "INBOX", "q" => "after:#{from.to_i}"))
      .to_return({ status: 200, headers: json, body: { messages: [ { id: "a" } ], nextPageToken: "p2" }.to_json })
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/messages")
      .with(query: hash_including("pageToken" => "p2"))
      .to_return({ status: 200, headers: json, body: { messages: [ { id: "b" } ] }.to_json })

    expect(adapter.inbox_message_ids_after(from)).to eq(%w[a b])
  end

  it "adds an epoch upper bound when before: is given" do
    before_time = Time.utc(2026, 1, 11)
    stub = stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/messages")
      .with(query: hash_including("labelIds" => "INBOX", "q" => "after:#{from.to_i} before:#{before_time.to_i}"))
      .to_return({ status: 200, headers: json, body: { messages: [ { id: "a" } ] }.to_json })

    expect(adapter.inbox_message_ids_after(from, before: before_time)).to eq(%w[a])
    expect(stub).to have_been_requested
  end

  it "never sends a YYYY/MM/DD date, which Gmail reads as Pacific time" do
    stub = stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/messages")
      .with(query: hash_including({})) { |request| request.uri.query_values["q"] !~ %r{\d{4}/\d{2}/\d{2}} }
      .to_return({ status: 200, headers: json, body: {}.to_json })

    adapter.inbox_message_ids_after(from, before: Time.utc(2026, 1, 11))

    expect(stub).to have_been_requested
  end
end
