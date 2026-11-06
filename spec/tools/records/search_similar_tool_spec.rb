require 'rails_helper'

RSpec.describe Records::SearchSimilarTool do
  subject(:tool) { described_class.new }

  let!(:google) { create(:interview, company: 'Google', job_title: 'Software Engineer') }

  before do
    create(:interview, company: 'Google LLC',  job_title: 'Software Engineer')
    create(:interview, company: 'Google Inc.', job_title: 'SWE')
    create(:interview, company: 'Acme Corp', job_title: 'Designer')
  end

  describe '#execute' do
    it 'finds rows with a matching substring' do
      result = tool.execute(table: 'interviews', column: 'company', value: 'Google')
      values = result[:matches].pluck(:value)
      expect(values).to include('Google', 'Google LLC', 'Google Inc.')
      expect(values).not_to include('Acme Corp')
    end

    it 'returns ids alongside each matched value' do
      result = tool.execute(table: 'interviews', column: 'company', value: 'Google')
      google_match = result[:matches].find { |m| m[:value] == 'Google' }
      expect(google_match[:ids]).to eq([ google.id ])
    end

    it 'groups multiple rows with the same value under one entry' do
      create(:interview, company: 'Google', job_title: 'PM').tap do |dup|
        result = tool.execute(table: 'interviews', column: 'company', value: 'Google')
        google_match = result[:matches].find { |m| m[:value] == 'Google' }
        expect(google_match[:ids]).to contain_exactly(google.id, dup.id)
      end
    end

    it 'finds rows where the stored value is a partial of the query' do
      result = tool.execute(table: 'interviews', column: 'company', value: 'Google Incorporated')
      values = result[:matches].pluck(:value)
      expect(values).to include('Google', 'Google LLC', 'Google Inc.')
    end

    it 'finds phonetically similar values via soundex' do
      result = tool.execute(table: 'interviews', column: 'job_title', value: 'Softwear Enginear')
      values = result[:matches].pluck(:value)
      expect(values).to include('Software Engineer')
    end

    it 'returns distinct value entries only' do
      result = tool.execute(table: 'interviews', column: 'job_title', value: 'Software Engineer')
      values = result[:matches].pluck(:value)
      expect(values.uniq).to eq(values)
    end

    it 'returns empty matches when nothing is similar' do
      result = tool.execute(table: 'interviews', column: 'company', value: 'xyzzy')
      expect(result[:matches]).to eq([])
    end

    it 'returns an error for an unknown table' do
      result = tool.execute(table: 'unknown', column: 'company', value: 'Google')
      expect(result[:error]).to match(/Unknown table/)
    end

    it 'returns an error for an unknown column' do
      result = tool.execute(table: 'interviews', column: 'nonexistent', value: 'Google')
      expect(result[:error]).to match(/Unknown column/)
    end
  end
end
