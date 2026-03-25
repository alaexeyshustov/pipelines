require 'yaml/store'

module GmailHelpers
  CREDENTIALS_PATH = Rails.root.join('spec/fixtures/files/gmail_credentials.json').to_s
  TOKEN_PATH       = Rails.root.join('tmp/test_gmail_token.yaml').to_s
  GMAIL_BASE_URL   = 'https://gmail.googleapis.com/gmail/v1/users/me'.freeze

  def setup_gmail
    store = YAML::Store.new(TOKEN_PATH)
    store.transaction do
      store['default'] = {
        'client_id'                => 'test_client_id.apps.googleusercontent.com',
        'access_token'             => 'test_access_token',
        'refresh_token'            => 'test_refresh_token',
        'scope'                    => 'https://www.googleapis.com/auth/gmail.modify',
        'expiration_time_millis'   => 9_999_999_999_999
      }.to_json
    end

    Emails.configure(gmail: { credentials_path: CREDENTIALS_PATH, token_path: TOKEN_PATH })
  end

  def teardown_gmail
    File.delete(TOKEN_PATH) if File.exist?(TOKEN_PATH)
    Emails.instance_variable_set(:@provider_registry, nil)
  end

  def gmail_message_json(id: 'msg1', subject: 'Test Subject', from: 'sender@example.com',
                         date: 'Mon, 1 Jan 2026 12:00:00 +0000')
    {
      id: id,
      threadId: "thread_#{id}",
      snippet: 'Test snippet',
      labelIds: [ 'INBOX' ],
      payload: {
        headers: [
          { name: 'Subject', value: subject },
          { name: 'From', value: from },
          { name: 'To', value: 'me@example.com' },
          { name: 'Date', value: date }
        ]
      }
    }.to_json
  end
end

RSpec.shared_context 'with gmail configured' do
  include GmailHelpers

  before { setup_gmail }
  after  { teardown_gmail }
end
