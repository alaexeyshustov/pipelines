require 'rails_helper'

RSpec.describe GetLabelsTool do
  subject(:tool) { described_class.new }

  include_context 'with gmail configured'


  let(:gmail_base) { GmailHelpers::GMAIL_BASE_URL }

  before do
    stub_request(:get, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/labels/)
      .to_return(
        status: 200,
        body: {
          labels: [
            { id: 'INBOX', name: 'INBOX', type: 'system' },
            { id: 'Label_1', name: 'applications', type: 'user' }
          ]
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  it 'returns the list of labels' do
    result = tool.execute(provider: 'gmail')
    expect(result).to be_an(Array)
    expect(result.map { |l| l[:name] }).to include('INBOX', 'applications')
  end

  it 'fetches labels from the Gmail API' do
    tool.execute(provider: 'gmail')
    expect(a_request(:get, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/labels/)).to have_been_made
  end
end
