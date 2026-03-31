require 'rails_helper'

RSpec.describe Emails::GetTool do
  subject(:tool) { described_class.new }

  include_context 'with gmail configured'

  let(:cache_dir) { described_class::CACHE_DIR }
  let(:cache_file) { cache_dir.join('gmail_msg_abc_.json') }

  before do
    FileUtils.rm_f(cache_file)

    stub_request(:get, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages\/msg_abc/)
      .to_return(
        status: 200,
        body: gmail_message_json(id: 'msg_abc', subject: 'Your application status', from: 'hr@company.com'),
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  after { FileUtils.rm_f(cache_file) }

  it 'returns the email content' do
    result = tool.execute(provider: 'gmail', message_id: 'msg_abc')
    expect(result).to include(id: 'msg_abc', subject: 'Your application status', from: 'hr@company.com')
  end

  it 'fetches the message with full format' do
    tool.execute(provider: 'gmail', message_id: 'msg_abc')
    expect(
      a_request(:get, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages\/msg_abc/).with { |req|
        URI.decode_www_form(URI.parse(req.uri).query.to_s).to_h['format'] == 'full'
      }
    ).to have_been_made
  end

  it 'writes a cache file after the first fetch' do
    tool.execute(provider: 'gmail', message_id: 'msg_abc')
    expect(cache_file).to exist
  end

  it 'returns cached data and skips the network on the second call' do
    tool.execute(provider: 'gmail', message_id: 'msg_abc')

    result = tool.execute(provider: 'gmail', message_id: 'msg_abc')
    expect(result).to include(id: 'msg_abc', subject: 'Your application status')
    expect(a_request(:get, /msg_abc/)).to have_been_made.once
  end

  context 'with multiple message ids' do
    before do
      stub_request(:get, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages\/msg_xyz/)
        .to_return(
          status: 200,
          body: gmail_message_json(id: 'msg_xyz', subject: 'Another email', from: 'other@company.com'),
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    after { FileUtils.rm_f(cache_dir.join('gmail_msg_xyz_.json')) }

    it 'uses separate cache files per provider and message_id' do
      tool.execute(provider: 'gmail', message_id: 'msg_abc')
      tool.execute(provider: 'gmail', message_id: 'msg_xyz')

      expect(cache_dir.join('gmail_msg_abc_.json')).to exist
      expect(cache_dir.join('gmail_msg_xyz_.json')).to exist
    end
  end
end
