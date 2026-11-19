require 'yaml/store'

module GmailHelpers
  CREDENTIALS_PATH = Rails.root.join('spec/fixtures/files/gmail_credentials.json').to_s
  GMAIL_BASE_URL   = 'https://gmail.googleapis.com/gmail/v1/users/me'.freeze

  # Per-process path: computed fresh on every call (never memoized) so
  # concurrent mutant workers each own a distinct token file on disk.
  def self.token_path
    Rails.root.join("tmp/test_gmail_token.#{Process.pid}.yaml").to_s
  end

  # The Gmail paths are server config, so the adapter is configured through ENV; teardown_gmail restores it.
  def setup_gmail
    write_gmail_token
    @saved_gmail_env = ENV.values_at('GMAIL_CREDENTIALS_PATH', 'GMAIL_TOKEN_PATH')
    ENV['GMAIL_CREDENTIALS_PATH'] = CREDENTIALS_PATH
    ENV['GMAIL_TOKEN_PATH']       = GmailHelpers.token_path
    Emails.configure(gmail: {})
  end

  def teardown_gmail
    FileUtils.rm_f(GmailHelpers.token_path)
    ENV['GMAIL_CREDENTIALS_PATH'], ENV['GMAIL_TOKEN_PATH'] = @saved_gmail_env if @saved_gmail_env
    Emails.instance_variable_set(:@provider_registry, nil)
  end

  def write_gmail_token(path = GmailHelpers.token_path)
    store = YAML::Store.new(path)
    store.transaction do
      store['default'] = {
        'client_id'                => 'test_client_id.apps.googleusercontent.com',
        'access_token'             => 'test_access_token',
        'refresh_token'            => 'test_refresh_token',
        'scope'                    => 'https://www.googleapis.com/auth/gmail.modify',
        'expiration_time_millis'   => 9_999_999_999_999
      }.to_json
    end
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

# Gmail paths are server config (GMAIL_CREDENTIALS_PATH / GMAIL_TOKEN_PATH), never request or row input. Override the
# lets to point an example somewhere else; the token file lives in a throwaway directory.
RSpec.shared_context 'with gmail paths from env' do
  let(:gmail_credentials_path) { GmailHelpers::CREDENTIALS_PATH }
  let(:gmail_token_dir)        { Dir.mktmpdir('gmail_token') }
  let(:gmail_token_path)       { File.join(gmail_token_dir, 'token.yaml') }

  around do |example|
    saved = ENV.values_at('GMAIL_CREDENTIALS_PATH', 'GMAIL_TOKEN_PATH')
    ENV['GMAIL_CREDENTIALS_PATH'] = gmail_credentials_path
    ENV['GMAIL_TOKEN_PATH']       = gmail_token_path
    example.run
  ensure
    ENV['GMAIL_CREDENTIALS_PATH'], ENV['GMAIL_TOKEN_PATH'] = saved
    FileUtils.rm_rf(gmail_token_dir)
  end
end
