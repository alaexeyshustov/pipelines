require 'rails_helper'

RSpec.describe ApplicationMail do
  describe 'validations' do
    it 'is valid with required attributes' do
      mail = build(:application_mail)
      expect(mail).to be_valid
    end

    it_behaves_like 'requires attribute', :date, :application_mail
    it_behaves_like 'requires attribute', :provider, :application_mail
    it_behaves_like 'requires attribute', :email_id, :application_mail

    it 'enforces uniqueness of email_id' do
      create(:application_mail, email_id: 'unique@example.com')
      duplicate = build(:application_mail, email_id: 'unique@example.com')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email_id]).not_to be_empty
    end

    it 'allows nil company, job_title, and action' do
      mail = build(:application_mail, company: nil, job_title: nil, action: nil)
      expect(mail).to be_valid
    end
  end

  describe '.as_rows' do
    it 'returns records as hashes with COLUMN_NAMES keys' do
      create(:application_mail, date: '2026-01-01', provider: 'gmail', email_id: 'a@gmail.com',
             company: 'Acme', job_title: 'Engineer', action: 'applied')

      rows = described_class.as_rows
      expect(rows.length).to eq(1)
      expect(rows.first.keys).to match_array(ApplicationMail::COLUMN_NAMES)
    end

    it 'orders records by date ascending' do
      create(:application_mail, date: '2026-03-01', email_id: 'b@gmail.com')
      create(:application_mail, date: '2026-01-01', email_id: 'a@gmail.com')

      dates = described_class.as_rows.map { |r| r['date'] }
      expect(dates).to eq(dates.sort)
    end

    it 'converts all values to strings' do
      create(:application_mail, date: Date.new(2026, 1, 1), email_id: 'test@gmail.com')

      row = described_class.as_rows.first
      expect(row.values).to all(be_a(String).or(be_nil))
    end

    it 'returns empty array when no records exist' do
      expect(described_class.as_rows).to eq([])
    end

    it 'accepts a custom scope' do
      gmail  = create(:application_mail, provider: 'gmail',  email_id: 'g@gmail.com')
      _yahoo = create(:application_mail, provider: 'yahoo',  email_id: 'y@yahoo.com')

      rows = described_class.as_rows(described_class.where(provider: 'gmail'))
      expect(rows.length).to eq(1)
      expect(rows.first['provider']).to eq('gmail')
    end
  end

  describe '.groupped' do
    it 'groups records by company and job_title' do
      create(:application_mail, company: 'Acme', job_title: 'Engineer', email_id: 'a@x.com')
      create(:application_mail, company: 'Acme', job_title: 'Engineer', email_id: 'b@x.com')

      rows = described_class.groupped
      expect(rows.length).to eq(1)
      expect(rows.first.company).to eq('Acme')
    end
  end

  describe 'COLUMN_NAMES' do
    it 'contains all expected column names' do
      expect(ApplicationMail::COLUMN_NAMES).to eq(%w[date provider email_id company job_title action])
    end
  end
end
