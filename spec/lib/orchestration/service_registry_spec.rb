require 'rails_helper'

RSpec.describe Orchestration::ServiceRegistry do
  describe '.lookup' do
    it 'returns Orchestration::Executors::EmailsFetcher for its class name' do
      expect(described_class.lookup("Orchestration::Executors::EmailsFetcher")).to eq(Orchestration::Executors::EmailsFetcher)
    end

    it 'returns Orchestration::Executors::Ingestion for its class name' do
      expect(described_class.lookup("Orchestration::Executors::Ingestion")).to eq(Orchestration::Executors::Ingestion)
    end

    it 'returns Orchestration::Executors::Query for its class name' do
      expect(described_class.lookup("Orchestration::Executors::Query")).to eq(Orchestration::Executors::Query)
    end

    it 'returns Orchestration::Executors::InterviewsGistExporter for its class name' do
      expect(described_class.lookup("Orchestration::Executors::InterviewsGistExporter")).to eq(Orchestration::Executors::InterviewsGistExporter)
    end

    it 'returns nil for an unknown class name' do
      expect(described_class.lookup("Unknown::Class")).to be_nil
    end

    it 'returns nil when name is nil' do
      expect(described_class.lookup(nil)).to be_nil
    end
  end
end
