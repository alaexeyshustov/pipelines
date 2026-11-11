require "rails_helper"

RSpec.describe Emails::Adapters::GmailAdapter, "#fetch_message" do
  include GmailHelpers

  subject(:adapter) do
    described_class.from_env(credentials_path: GmailHelpers::CREDENTIALS_PATH, token_path: GmailHelpers.token_path)
  end

  let(:json) { { "Content-Type" => "application/json" } }
  let(:payload) do
    { mimeType: "multipart/alternative",
      headers: [ { name: "Subject", value: "Interview" }, { name: "From", value: "HR <hr@acme.com>" },
                 { name: "To", value: "me@gmail.com" }, { name: "Date", value: "Mon, 5 Jan 2026 12:30:00 +0100" } ],
      parts: [ { mimeType: "text/plain", body: { data: b64("plain text") } },
               { mimeType: "text/html", body: { data: b64("<p>html text</p>") } } ] }
  end

  before { setup_gmail }
  after  { teardown_gmail }

  def b64(text) = Base64.urlsafe_encode64(text)


  def stub_message(**extra)
    stub_request(:get, %r{#{GmailHelpers::GMAIL_BASE_URL}/messages/m1\?format=full}o)
      .to_return(status: 200, headers: json, body: { id: "m1", threadId: "t1", payload: payload, **extra }.to_json)
  end

  it "returns plain and html bodies, a web link and a parsed date" do
    stub_message
    expect(adapter.fetch_message("m1")).to include(
      id: "m1", provider: "gmail", subject: "Interview", from: "HR <hr@acme.com>", to: "me@gmail.com",
      body: "plain text", html_body: "<p>html text</p>",
      source_url: "https://mail.google.com/mail/u/0/#inbox/m1",
      date: Time.utc(2026, 1, 5, 11, 30)
    )
  end

  it "returns nil html_body for a plain-text-only message" do
    payload[:parts] = payload[:parts].first(1)
    stub_message

    expect(adapter.fetch_message("m1")).to include(body: "plain text", html_body: nil)
  end

  it "falls back to internalDate when the Date header is missing" do
    payload[:headers].reject! { |header| header[:name] == "Date" }
    stub_message(internalDate: "1767614400000")

    expect(adapter.fetch_message("m1")[:date]).to eq(Time.at(1_767_614_400).utc)
  end
end
