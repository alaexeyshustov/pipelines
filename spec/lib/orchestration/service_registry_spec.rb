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

    it 'returns Orchestration::Executors::DriveDocumentsSync for its class name' do
      expect(described_class.lookup("Orchestration::Executors::DriveDocumentsSync")).to eq(Orchestration::Executors::DriveDocumentsSync)
    end

    %w[EmailsList EmailsClassify EmailsEmbed AttachmentsIngest DocumentsClassify DocumentsEmbed].each do |name|
      it "returns Orchestration::Executors::#{name} for its class name" do
        expect(described_class.lookup("Orchestration::Executors::#{name}")).to eq("Orchestration::Executors::#{name}".constantize)
      end
    end

    it 'returns nil for an unknown class name' do
      expect(described_class.lookup("Unknown::Class")).to be_nil
    end

    it 'returns nil when name is nil' do
      expect(described_class.lookup(nil)).to be_nil
    end
  end

  describe 'REGISTRY' do
    it 'lists the six email ingestion executors' do
      expect(described_class::REGISTRY.keys).to include(
        "Orchestration::Executors::EmailsList", "Orchestration::Executors::EmailsClassify",
        "Orchestration::Executors::EmailsEmbed", "Orchestration::Executors::AttachmentsIngest",
        "Orchestration::Executors::DocumentsClassify", "Orchestration::Executors::DocumentsEmbed"
      )
    end

    it 'encodes the new executors as agent keywords' do
      expect(Orchestration::AgentClassKeyword.encode("Orchestration::Executors::EmailsList")).to eq("agent_emails_list")
      expect(Orchestration::AgentClassKeyword.encode("Orchestration::Executors::AttachmentsIngest")).to eq("agent_attachments_ingest")
    end

    it 'gives every ingestion executor an input_schema and an output_schema' do
      %w[EmailsList EmailsClassify EmailsEmbed AttachmentsIngest DocumentsClassify DocumentsEmbed].each do |name|
        executor = described_class.lookup("Orchestration::Executors::#{name}")
        expect(executor.input_schema).to include("type" => "object")
        expect(executor.output_schema).to include("type" => "object")
      end
    end
  end
end
