require 'rails_helper'

RSpec.describe Records::SearchSimilarTool do
  subject(:tool) { described_class.new }

  before do
    create(:application_mail, company: 'Google',      job_title: 'Software Engineer', email_id: 'a@x.com')
    create(:application_mail, company: 'Google LLC',  job_title: 'Software Engineer', email_id: 'b@x.com')
    create(:application_mail, company: 'Google Inc.', job_title: 'SWE',               email_id: 'c@x.com')
    create(:application_mail, company: 'Acme Corp',   job_title: 'Designer',          email_id: 'd@x.com')
  end

  describe '#execute' do
    it 'finds rows with a matching substring' do
      result = tool.execute(table: 'application_mails', column: 'company', value: 'Google')
      expect(result[:matches]).to include('Google', 'Google LLC', 'Google Inc.')
      expect(result[:matches]).not_to include('Acme Corp')
    end

    it 'finds rows where the stored value is a partial of the query' do
      result = tool.execute(table: 'application_mails', column: 'company', value: 'Google Incorporated')
      expect(result[:matches]).to include('Google', 'Google LLC', 'Google Inc.')
    end

    it 'finds phonetically similar values via soundex' do
      result = tool.execute(table: 'application_mails', column: 'job_title', value: 'Softwear Enginear')
      expect(result[:matches]).to include('Software Engineer')
    end

    it 'returns distinct values only' do
      result = tool.execute(table: 'application_mails', column: 'job_title', value: 'Software Engineer')
      expect(result[:matches].uniq).to eq(result[:matches])
    end

    it 'returns empty matches when nothing is similar' do
      result = tool.execute(table: 'application_mails', column: 'company', value: 'xyzzy')
      expect(result[:matches]).to eq([])
    end

    it 'raises ArgumentError for an unknown table' do
      expect { tool.execute(table: 'unknown', column: 'company', value: 'Google') }
        .to raise_error(ArgumentError, /Unknown table/)
    end

    it 'raises ArgumentError for an unknown column' do
      expect { tool.execute(table: 'application_mails', column: 'nonexistent', value: 'Google') }
        .to raise_error(ArgumentError, /Unknown column/)
    end
  end
end
