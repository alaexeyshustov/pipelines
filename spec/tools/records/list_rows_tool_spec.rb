require 'rails_helper'

RSpec.describe Records::ListRowsTool do
  subject(:tool) { described_class.new }

  describe 'interviews' do
    before do
      create(:interview, company: 'Acme', job_title: 'Engineer')
      create(:interview, company: 'Globex', job_title: 'Designer')
      create(:interview, company: 'Initech', job_title: 'Manager')
    end

    it 'returns all rows with headers' do
      result = tool.execute(table: 'interviews')
      expect(result[:headers]).to eq(Interview::COLUMN_NAMES)
      expect(result[:row_count]).to eq(3)
    end

    it 'limits the number of rows returned' do
      result = tool.execute(table: 'interviews', limit: 2)
      expect(result[:row_count]).to eq(2)
    end

    it 'skips rows with a positive offset' do
      result = tool.execute(table: 'interviews', offset: 1)
      expect(result[:row_count]).to eq(2)
    end

    it 'returns zero rows when offset exceeds total' do
      result = tool.execute(table: 'interviews', offset: 10)
      expect(result[:row_count]).to eq(0)
    end
  end

  it_behaves_like 'a records tool that handles unknown tables'
end
