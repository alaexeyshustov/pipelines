require 'rails_helper'

RSpec.describe Records::ReadSchemaTool do
  subject(:tool) { described_class.new }

  it 'returns column names for application_mails' do
    result = tool.execute(table: 'application_mails')
    expect(result).to eq(headers: ApplicationMail::COLUMN_NAMES)
  end

  it 'returns column names for interviews' do
    result = tool.execute(table: 'interviews')
    expect(result).to eq(headers: Interview::COLUMN_NAMES)
  end

  it 'returns an error for an unknown table' do
    result = tool.execute(table: 'unknown')
    expect(result[:error]).to match(/Unknown table/)
  end
end
