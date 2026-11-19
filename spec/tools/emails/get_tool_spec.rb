require 'rails_helper'

RSpec.describe Emails::GetTool do
  subject(:tool) { described_class.new }

  include_context 'with gmail configured'

  let(:message_path) { %r{gmail\.googleapis\.com/gmail/v1/users/me/messages/msg_abc} }

  before do
    FileUtils.rm_rf(Rails.root.join('tmp/cache/emails')) # stale cache from the pre-change implementation

    stub_request(:get, message_path)
      .to_return(
        status: 200,
        body: gmail_message_json(id: 'msg_abc', subject: 'Your application status', from: 'hr@company.com'),
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  it 'returns the email content' do
    result = tool.execute(provider: 'gmail', message_id: 'msg_abc')
    expect(result).to include(id: 'msg_abc', subject: 'Your application status', from: 'hr@company.com')
  end

  it 'fetches the message with full format' do
    tool.execute(provider: 'gmail', message_id: 'msg_abc')
    expect(
      a_request(:get, message_path).with { |req|
        URI.decode_www_form(URI.parse(req.uri).query.to_s).to_h['format'] == 'full'
      }
    ).to have_been_made
  end

  it 'has no disk cache constant' do
    expect(described_class.const_defined?(:CACHE_DIR, false)).to be false
  end

  it 'fetches from the network on every call and writes no cache file' do
    cache_dir = Rails.root.join('tmp/cache/emails')
    FileUtils.rm_rf(cache_dir)

    2.times { tool.execute(provider: 'gmail', message_id: 'msg_abc') }

    expect(a_request(:get, message_path)).to have_been_made.twice
    expect(cache_dir).not_to exist
  end

  context 'with an unknown provider' do
    before { allow(Emails).to receive(:message) }

    [ '../../etc/passwd', 'outlook', '' ].each do |provider|
      it "returns an error without calling Emails.message for #{provider.inspect}" do
        result = tool.execute(provider: provider, message_id: 'msg_abc')

        expect(result).to include(:error)
        expect(Emails).not_to have_received(:message)
      end
    end
  end

  context 'with a long body' do
    let(:body_limit) { 32 * 1024 }

    def stub_body(text)
      allow(Emails).to receive(:message).and_return(id: 'msg_abc', subject: 's', body: text)
    end

    it 'leaves a short body untouched' do
      stub_body('short body')
      expect(tool.execute(provider: 'gmail', message_id: 'msg_abc')[:body]).to eq('short body')
    end

    it 'truncates a body over 32 KB to 32 KB including a marker' do
      stub_body('a' * (body_limit * 2))
      body = tool.execute(provider: 'gmail', message_id: 'msg_abc')[:body]

      expect(body.bytesize).to be <= body_limit
      expect(body).to match(/trunc/i)
    end

    it 'keeps multibyte text valid when cutting' do
      stub_body('é' * body_limit)
      body = tool.execute(provider: 'gmail', message_id: 'msg_abc')[:body]

      expect(body).to be_valid_encoding
      expect(body.bytesize).to be <= body_limit
      expect(body).to match(/trunc/i)
    end

    it 'does not touch a body of exactly 32 KB' do
      stub_body('a' * body_limit)
      expect(tool.execute(provider: 'gmail', message_id: 'msg_abc')[:body]).to eq('a' * body_limit)
    end
  end
end
