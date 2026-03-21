require 'rails_helper'

RSpec.describe Interview, type: :model do
  describe 'validations' do
    it 'is valid with required attributes' do
      interview = build(:interview)
      expect(interview).to be_valid
    end

    it 'requires company' do
      interview = build(:interview, company: nil)
      expect(interview).not_to be_valid
      expect(interview.errors[:company]).not_to be_empty
    end

    it 'requires job_title' do
      interview = build(:interview, job_title: nil)
      expect(interview).not_to be_valid
      expect(interview.errors[:job_title]).not_to be_empty
    end

    it 'enforces uniqueness of job_title scoped to company' do
      create(:interview, company: 'Acme', job_title: 'Engineer')
      duplicate = build(:interview, company: 'Acme', job_title: 'Engineer')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:job_title]).not_to be_empty
    end

    it 'allows same job_title for different companies' do
      create(:interview, company: 'Acme',   job_title: 'Engineer')
      other = build(:interview, company: 'Globex', job_title: 'Engineer')
      expect(other).to be_valid
    end
  end

  describe 'STATUSES' do
    it 'contains the expected status values' do
      expect(Interview::STATUSES).to eq(%w[pending_reply having_interviews rejected offer_received])
    end
  end

  describe '.as_rows' do
    it 'returns records as hashes with COLUMN_NAMES keys' do
      create(:interview, company: 'Acme', job_title: 'Engineer 1')

      rows = Interview.as_rows
      expect(rows.length).to eq(1)
      expect(rows.first.keys).to match_array(Interview::COLUMN_NAMES)
    end

    it 'orders records by company then job_title' do
      create(:interview, company: 'Zeta',  job_title: 'Dev 1')
      create(:interview, company: 'Alpha', job_title: 'Dev 2')
      create(:interview, company: 'Alpha', job_title: 'Dev 1')

      rows = Interview.as_rows
      expect(rows.map { |r| [ r['company'], r['job_title'] ] }).to eq([
        [ 'Alpha', 'Dev 1' ],
        [ 'Alpha', 'Dev 2' ],
        [ 'Zeta',  'Dev 1' ]
      ])
    end

    it 'converts values to strings, allowing nil' do
      create(:interview, company: 'Acme', job_title: 'Engineer 2', rejected_at: nil)

      row = Interview.as_rows.first
      row.each_value { |v| expect(v).to be_a(String).or(be_nil) }
    end

    it 'returns empty array when no records exist' do
      expect(Interview.as_rows).to eq([])
    end

    it 'accepts a custom scope' do
      create(:interview, company: 'Acme',   job_title: 'Engineer 3', status: 'rejected')
      create(:interview, company: 'Globex', job_title: 'Engineer 4', status: 'pending_reply')

      rows = Interview.as_rows(Interview.where(status: 'rejected'))
      expect(rows.length).to eq(1)
      expect(rows.first['company']).to eq('Acme')
    end
  end

  describe 'COLUMN_NAMES' do
    it 'contains all expected column names' do
      expect(Interview::COLUMN_NAMES).to eq(%w[
        company job_title status applied_at rejected_at
        first_interview_at second_interview_at third_interview_at fourth_interview_at
      ])
    end
  end
end
