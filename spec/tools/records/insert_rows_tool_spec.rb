require 'rails_helper'

RSpec.describe Records::InsertRowsTool do
  subject(:tool) { described_class.new }

  describe 'application_mails' do
    let(:row) { { 'date' => '2026-01-15', 'provider' => 'gmail', 'email_id' => 'abc123', 'company' => 'Acme', 'job_title' => 'Engineer', 'action' => 'Applied' } }

    it 'inserts a valid row and returns the count' do
      result = tool.execute(table: 'application_mails', data: [ row ].to_json)
      expect(result[:rows_added]).to eq(1)
      expect(ApplicationMail.count).to eq(1)
    end

    it 'skips duplicate email_ids and returns the existing id' do
      existing = create(:application_mail, email_id: 'abc123')
      result = tool.execute(table: 'application_mails', data: [ row ].to_json)
      expect(result[:rows_added]).to eq(0)
      expect(ApplicationMail.count).to eq(1)
      expect(result[:duplicate]).to eq([ { existing_id: existing.id } ])
    end

    it 'skips rows missing required columns' do
      result = tool.execute(table: 'application_mails', data: [ { 'company' => 'Acme' } ].to_json)
      expect(result[:rows_added]).to eq(0)
    end
  end

  describe 'interviews' do
    let(:row) { { 'company' => 'Globex', 'job_title' => 'Developer', 'status' => 'pending_reply' } }

    it 'inserts a valid row and returns the count' do
      result = tool.execute(table: 'interviews', data: [ row ].to_json)
      expect(result[:rows_added]).to eq(1)
      expect(Interview.count).to eq(1)
    end

    it 'skips duplicate company+job_title pairs and returns the existing id' do
      existing = create(:interview, company: 'Globex', job_title: 'Developer')
      result = tool.execute(table: 'interviews', data: [ row ].to_json)
      expect(result[:rows_added]).to eq(0)
      expect(result[:duplicate]).to eq([ { existing_id: existing.id } ])
    end
  end

  it 'raises ArgumentError when data is not a JSON array' do
    expect { tool.execute(table: 'application_mails', data: '{}') }.to raise_error(ArgumentError, /must be a JSON array/)
  end

  it 'returns invalid_data status when data is not valid JSON' do
    result = tool.execute(table: 'application_mails', data: 'not-json')
    expect(result[:status]).to eq('invalid_data')
    expect(result[:error]).to be_present
  end

  it 'returns an error for an unknown table' do
    result = tool.execute(table: 'unknown', data: '[]')
    expect(result[:status]).to eq('insert_failed')
    expect(result[:error]).to match(/Unknown table/)
  end
end
