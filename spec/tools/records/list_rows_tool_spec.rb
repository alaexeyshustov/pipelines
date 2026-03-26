# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Records::ListRowsTool do
  subject(:tool) { described_class.new }

  describe 'application_mails' do
    before do
      create(:application_mail, company: 'Acme',  job_title: 'Engineer', date: '2026-01-01', email_id: 'a@x.com')
      create(:application_mail, company: 'Globex', job_title: 'Designer', date: '2026-02-01', email_id: 'b@x.com')
      create(:application_mail, company: 'Initech', job_title: 'Manager', date: '2026-03-01', email_id: 'c@x.com')
    end

    it 'returns all rows with headers' do
      result = tool.execute(table: 'application_mails')
      expect(result[:headers]).to eq(ApplicationMail::COLUMN_NAMES)
      expect(result[:row_count]).to eq(3)
    end

    it 'limits the number of rows returned' do
      result = tool.execute(table: 'application_mails', limit: 2)
      expect(result[:row_count]).to eq(2)
    end

    it 'skips rows with a positive offset' do
      result = tool.execute(table: 'application_mails', offset: 1)
      expect(result[:row_count]).to eq(2)
    end

    it 'returns zero rows when offset exceeds total' do
      result = tool.execute(table: 'application_mails', offset: 10)
      expect(result[:row_count]).to eq(0)
    end
  end

  describe 'interviews' do
    before do
      create(:interview, company: 'Acme', job_title: 'Engineer')
    end

    it 'returns all rows with headers' do
      result = tool.execute(table: 'interviews')
      expect(result[:headers]).to eq(Interview::COLUMN_NAMES)
      expect(result[:row_count]).to eq(1)
    end
  end

  it 'raises ArgumentError for an unknown table' do
    expect { tool.execute(table: 'unknown') }.to raise_error(ArgumentError, /Unknown table/)
  end
end
