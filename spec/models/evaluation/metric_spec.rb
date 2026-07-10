require 'rails_helper'

RSpec.describe Evaluation::Metric do
  describe 'validations' do
    it 'is valid with required attributes' do
      metric = build(:evaluation_metric)
      expect(metric).to be_valid
    end

    it 'requires agent_name' do
      metric = build(:evaluation_metric, agent_name: nil)
      expect(metric).not_to be_valid
      expect(metric.errors[:agent_name]).to be_present
    end

    it 'requires name' do
      metric = build(:evaluation_metric, name: nil)
      expect(metric).not_to be_valid
      expect(metric.errors[:name]).to be_present
    end

    it 'requires description' do
      metric = build(:evaluation_metric, description: nil)
      expect(metric).not_to be_valid
      expect(metric.errors[:description]).to be_present
    end

    it 'requires weight' do
      metric = build(:evaluation_metric, weight: nil)
      expect(metric).not_to be_valid
      expect(metric.errors[:weight]).to be_present
    end

    it 'enforces uniqueness of name scoped to agent_name' do
      create(:evaluation_metric, agent_name: 'TestAgent', name: 'accuracy')
      duplicate = build(:evaluation_metric, agent_name: 'TestAgent', name: 'accuracy')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to be_present
    end

    it 'allows same name for different agents' do
      create(:evaluation_metric, agent_name: 'AgentA', name: 'accuracy')
      metric = build(:evaluation_metric, agent_name: 'AgentB', name: 'accuracy')
      expect(metric).to be_valid
    end
  end

  describe 'defaults' do
    it 'defaults weight to 1.0' do
      metric = described_class.new(agent_name: 'TestAgent', name: 'test', description: 'test desc')
      expect(metric.weight).to eq(1.0)
    end

    it 'defaults active to true' do
      metric = described_class.new(agent_name: 'TestAgent', name: 'test', description: 'test desc')
      expect(metric.active).to be true
    end
  end

  describe 'scopes' do
    let!(:active_metric)   { create(:evaluation_metric, agent_name: 'AgentA', active: true) }
    let!(:inactive_metric) { create(:evaluation_metric, agent_name: 'AgentA', name: 'inactive_m', active: false) }
    let!(:other_agent)     { create(:evaluation_metric, agent_name: 'AgentB', active: true) }

    describe '.for_agent' do
      it 'returns metrics for the given agent' do
        result = described_class.for_agent('AgentA')
        expect(result).to include(active_metric, inactive_metric)
        expect(result).not_to include(other_agent)
      end
    end

    describe '.active' do
      it 'returns only active metrics' do
        result = described_class.active
        expect(result).to include(active_metric, other_agent)
        expect(result).not_to include(inactive_metric)
      end
    end

    describe '.active_for_agent' do
      it 'returns only active metrics for the given agent' do
        result = described_class.active_for_agent('AgentA')
        expect(result).to include(active_metric)
        expect(result).not_to include(inactive_metric, other_agent)
      end
    end
  end
end
