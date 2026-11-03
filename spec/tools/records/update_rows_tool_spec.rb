require 'rails_helper'

RSpec.describe Records::UpdateRowsTool do
  subject(:tool) { described_class.new }

  describe 'interviews' do
    let!(:interview) { create(:interview, company: 'Globex', job_title: 'Developer') }

    it 'updates an interview record' do
      result = tool.execute(table: 'interviews', id: interview.id.to_s, data: '{"company":"New Globex"}')
      expect(result).to eq(status: 'row_updated')
      expect(interview.reload.company).to eq('New Globex')
    end

    it 'ignores columns not in COLUMN_NAMES' do
      result = tool.execute(table: 'interviews', id: interview.id.to_s, data: '{"nonexistent":"value"}')
      expect(result).to eq(status: 'row_updated')
    end

    it 'returns update_failed when record is not found' do
      result = tool.execute(table: 'interviews', id: '999999', data: '{"company":"X"}')
      expect(result[:status]).to eq('update_failed')
      expect(result[:error]).to be_present
    end

    it 'raises ArgumentError when data is not a JSON object' do
      expect {
        tool.execute(table: 'interviews', id: interview.id.to_s, data: '["not","an","object"]')
      }.to raise_error(ArgumentError, /data must be a JSON object/)
    end
  end

  it 'returns an error for an unknown table' do
    result = tool.execute(table: 'unknown', id: '1', data: '{}')
    expect(result[:status]).to eq('update_failed')
    expect(result[:error]).to match(/Unknown table/)
  end
end
