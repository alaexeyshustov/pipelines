require 'rails_helper'

RSpec.describe Records::ReadRowsTool do
  subject(:tool) { described_class.new }

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

  describe 'column_name validation' do
    before { create(:interview, company: 'Globex', job_title: 'Developer 1') }

    it 'returns an error for an unknown column_name' do
      result = tool.execute(table: 'interviews', column_name: 'nonexistent', column_value: 'x')
      expect(result).to include(:error)
      expect(result[:error]).to match(/Unknown column/)
    end

    it 'returns an error for a column_name that tries to inject SQL' do
      result = tool.execute(table: 'interviews', column_name: 'company = company OR 1', column_value: 'x')
      expect(result).to include(:error)
    end

    it 'still allows filtering by id' do
      row = create(:interview, company: 'Other Co', job_title: 'Developer 2')
      result = tool.execute(table: 'interviews', column_name: 'id', column_value: row.id.to_s)
      expect(result[:row_count]).to eq(1)
    end
  end

  it_behaves_like 'a records tool that handles unknown tables'
end
