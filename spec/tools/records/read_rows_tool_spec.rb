require 'rails_helper'

RSpec.describe Records::ReadRowsTool do
  subject(:tool) { described_class.new }

  describe 'application_mails' do
    before { create(:application_mail, company: 'Acme', job_title: 'Engineer') }

    it 'returns all rows with headers' do
      result = tool.execute(table: 'application_mails')
      expect(result[:headers]).to eq(ApplicationMail::COLUMN_NAMES)
      expect(result[:row_count]).to eq(1)
    end

    it 'filters rows by column value' do
      create(:application_mail, company: 'Other Corp', job_title: 'Designer')
      result = tool.execute(table: 'application_mails', column_name: 'company', column_value: 'Acme')
      expect(result[:row_count]).to eq(1)
      expect(result[:rows].first['company']).to eq('Acme')
    end
  end

  describe 'interviews' do
    before { create(:interview, company: 'Globex', job_title: 'Developer 1') }

    it 'returns all rows with headers' do
      result = tool.execute(table: 'interviews')
      expect(result[:headers]).to eq(Interview::COLUMN_NAMES)
      expect(result[:row_count]).to eq(1)
    end

    it 'filters rows by column value' do
      create(:interview, company: 'Other Co', job_title: 'Developer 2')
      result = tool.execute(table: 'interviews', column_name: 'company', column_value: 'Globex')
      expect(result[:row_count]).to eq(1)
      expect(result[:rows].first['company']).to eq('Globex')
    end
  end

  it 'raises ArgumentError for an unknown table' do
    expect { tool.execute(table: 'unknown') }.to raise_error(ArgumentError, /Unknown table/)
  end
end
