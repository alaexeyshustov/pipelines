require "rails_helper"

RSpec.describe Emails::Adapters::GmailAdapter, "#inbox_message_ids_since" do
  include GmailHelpers

  subject(:adapter) do
    described_class.from_env
  end

  let(:json) { { "Content-Type" => "application/json" } }

  before { setup_gmail }
  after  { teardown_gmail }

  def history_page(ids, next_page_token: nil)
    { history: [ { id: "1", messagesAdded: ids.map { |id| { message: { id: id, labelIds: %w[INBOX] } } } } ],
      nextPageToken: next_page_token }.compact.to_json
  end

  it "pages through history for messages added to INBOX, without repeats" do
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/history")
      .with(query: hash_including("startHistoryId" => "100", "labelId" => "INBOX"))
      .to_return({ status: 200, headers: json, body: history_page(%w[a b], next_page_token: "p2") })
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/history")
      .with(query: hash_including("pageToken" => "p2"))
      .to_return({ status: 200, headers: json, body: history_page(%w[b c]) })

    expect(adapter.inbox_message_ids_since("100")).to eq(%w[a b c])
  end

  it "asks for messageAdded and labelAdded history" do
    # Checked on the service call: WebMock collapses repeated query keys, so the URL cannot show both types.
    service = Google::Apis::GmailV1::GmailService.new
    allow(service).to receive(:list_user_histories).and_return(Google::Apis::GmailV1::ListHistoryResponse.new)

    Emails::Adapters::GmailInboxLister.new(service).since("100")

    expect(service).to have_received(:list_user_histories)
      .with("me", hash_including(history_types: %w[messageAdded labelAdded], label_id: "INBOX"))
  end

  it "returns a message that was given the INBOX label" do
    body = { history: [ { id: "2", labelsAdded: [ { message: { id: "m", labelIds: %w[INBOX] }, labelIds: %w[INBOX] } ] } ] }
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/history").with(query: hash_including("startHistoryId" => "100"))
      .to_return(status: 200, headers: json, body: body.to_json)

    expect(adapter.inbox_message_ids_since("100")).to eq(%w[m])
  end

  it "ignores messages that were given any other label" do
    body = { history: [ { id: "2", labelsAdded: [ { message: { id: "m", labelIds: %w[STARRED] }, labelIds: %w[STARRED] } ] } ] }
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/history").with(query: hash_including("startHistoryId" => "100"))
      .to_return(status: 200, headers: json, body: body.to_json)

    expect(adapter.inbox_message_ids_since("100")).to eq([])
  end

  it "returns an id once when it was both added and labelled" do
    body = { history: [ { id: "2", messagesAdded: [ { message: { id: "m" } } ],
                          labelsAdded: [ { message: { id: "m" }, labelIds: %w[INBOX] } ] } ] }
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/history").with(query: hash_including("startHistoryId" => "100"))
      .to_return(status: 200, headers: json, body: body.to_json)

    expect(adapter.inbox_message_ids_since("100")).to eq(%w[m])
  end

  it "returns no ids when nothing changed" do
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/history").with(query: hash_including({}))
      .to_return(status: 200, headers: json, body: { historyId: "101" }.to_json)

    expect(adapter.inbox_message_ids_since("100")).to eq([])
  end

  it "raises HistoryExpiredError when Gmail no longer has the history (404)" do
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/history").with(query: hash_including({}))
      .to_return(status: 404, headers: json, body: { error: { code: 404, message: "Not Found" } }.to_json)

    expect { adapter.inbox_message_ids_since("1") }.to raise_error(Emails::HistoryExpiredError)
  end
end
