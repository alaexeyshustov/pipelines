require 'rails_helper'

RSpec.describe CreateLabelTool do
  subject(:tool) { described_class.new }

  include_context 'with gmail configured'


  let(:gmail_base) { GmailHelpers::GMAIL_BASE_URL }

  before do
    stub_request(:post, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/labels/)
      .to_return(
        status: 200,
        body: { id: 'Label_new', name: 'applications', type: 'user' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  it 'returns the created label' do
    result = tool.execute(provider: 'gmail', name: 'applications')
    expect(result).to include(id: 'Label_new', name: 'applications')
  end

  it 'posts to the Gmail labels endpoint' do
    tool.execute(provider: 'gmail', name: 'applications')
    expect(
      a_request(:post, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/labels/).with { |req|
        JSON.parse(req.body)['name'] == 'applications'
      }
    ).to have_been_made
  end
end
