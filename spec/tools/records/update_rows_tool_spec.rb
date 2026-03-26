# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Records::UpdateRowsTool do
  subject(:tool) { described_class.new }

  describe 'application_mails' do
    let!(:mail) { create(:application_mail, company: 'Acme', job_title: 'Engineer') }

    it 'updates a record and returns success status' do
      result = tool.execute(table: 'application_mails', id: mail.id.to_s, data: '{"company":"New Acme"}')
      expect(result).to eq(status: 'row_updated')
      expect(mail.reload.company).to eq('New Acme')
    end

    it 'ignores columns not in COLUMN_NAMES' do
      result = tool.execute(table: 'application_mails', id: mail.id.to_s, data: '{"nonexistent":"value"}')
      expect(result).to eq(status: 'row_updated')
    end

    it 'returns update_failed when record is not found' do
      result = tool.execute(table: 'application_mails', id: '999999', data: '{"company":"X"}')
      expect(result[:status]).to eq('update_failed')
      expect(result[:error]).to be_present
    end

    it 'returns update_failed when a uniqueness constraint is violated' do
      other = create(:application_mail, email_id: 'other@example.com')
      allow(other).to receive(:update).and_raise(ActiveRecord::RecordNotUnique, 'duplicate')
      allow(ApplicationMail).to receive(:find).and_return(other)

      result = tool.execute(table: 'application_mails', id: other.id.to_s, data: '{"email_id":"taken"}')
      expect(result[:status]).to eq('update_failed')
    end

    it 'raises ArgumentError when data is not a JSON object' do
      expect {
        tool.execute(table: 'application_mails', id: mail.id.to_s, data: '["not","an","object"]')
      }.to raise_error(ArgumentError, /data must be a JSON object/)
    end
  end

  describe 'interviews' do
    let!(:interview) { create(:interview, company: 'Globex', job_title: 'Developer') }

    it 'updates an interview record' do
      result = tool.execute(table: 'interviews', id: interview.id.to_s, data: '{"company":"New Globex"}')
      expect(result).to eq(status: 'row_updated')
      expect(interview.reload.company).to eq('New Globex')
    end
  end

  it 'raises ArgumentError for an unknown table' do
    expect {
      tool.execute(table: 'unknown', id: '1', data: '{}')
    }.to raise_error(ArgumentError, /Unknown table/)
  end
end
