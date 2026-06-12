require 'rails_helper'

RSpec.describe Orchestration::ServiceRegistry do
  describe '.lookup' do
    it 'returns Emails::FetchExecutor for its class name' do
      expect(described_class.lookup("Emails::FetchExecutor")).to eq(Emails::FetchExecutor)
    end

    it 'returns Orchestration::IngestionExecutor for its class name' do
      expect(described_class.lookup("Orchestration::IngestionExecutor")).to eq(Orchestration::IngestionExecutor)
    end

    it 'returns Orchestration::QueryExecutor for its class name' do
      expect(described_class.lookup("Orchestration::QueryExecutor")).to eq(Orchestration::QueryExecutor)
    end

    it 'returns Interviews::GistExportExecutor for its class name' do
      expect(described_class.lookup("Interviews::GistExportExecutor")).to eq(Interviews::GistExportExecutor)
    end

    it 'returns nil for an unknown class name' do
      expect(described_class.lookup("Unknown::Class")).to be_nil
    end

    it 'returns nil when name is nil' do
      expect(described_class.lookup(nil)).to be_nil
    end
  end
end
