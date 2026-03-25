require 'rails_helper'

RSpec.describe ReadTableSchemaTool do
  subject(:tool) { described_class.new }

  it 'returns column names for application_mails' do
    result = tool.execute(table: 'application_mails')
    expect(result).to eq(headers: ApplicationMail::COLUMN_NAMES)
  end

  it 'returns column names for interviews' do
    result = tool.execute(table: 'interviews')
    expect(result).to eq(headers: Interview::COLUMN_NAMES)
  end

  it 'raises ArgumentError for an unknown table' do
    expect { tool.execute(table: 'unknown') }.to raise_error(ArgumentError, /Unknown table/)
  end
end
