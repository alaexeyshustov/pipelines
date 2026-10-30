require 'rails_helper'

RSpec.describe Orchestration::AgentClassKeyword do
  describe '.encode' do
    it 'encodes a registered class name string' do
      expect(described_class.encode("Orchestration::Executors::EmailsFetcher")).to eq("agent_emails_fetcher")
    end

    it 'encodes a class constant' do
      expect(described_class.encode(Orchestration::Executors::Query)).to eq("agent_query")
    end

    it 'raises UnknownKeyword for an unregistered class' do
      expect { described_class.encode("Object") }.to raise_error(described_class::UnknownKeyword)
    end
  end

  describe '.decode' do
    it 'raises UnknownKeyword for an unknown keyword' do
      expect { described_class.decode("agent_nope") }.to raise_error(described_class::UnknownKeyword, /agent_nope/)
    end

    Orchestration::ServiceRegistry::REGISTRY.each_key do |name|
      it "round-trips #{name}" do
        expect(described_class.decode(described_class.encode(name))).to eq(name)
      end
    end
  end
end
