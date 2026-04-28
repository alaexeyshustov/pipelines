require 'rails_helper'

RSpec.describe Evaluation::MetricExtractor do
  subject(:extractor) { described_class.new(agent_name) }

  let(:agent_name) { 'Emails::ClassifyAgent' }
  let(:instructions) { 'You are an email classifier. Classify emails by subject.' }
  let(:llm_response_body) do
    {
      id: 'msg_01',
      type: 'message',
      role: 'assistant',
      content: [
        {
          type: 'text',
          text: JSON.generate([
            { 'name' => 'classification_accuracy', 'description' => 'Measures how accurately emails are classified' },
            { 'name' => 'tag_relevance', 'description' => 'Evaluates whether suggested tags are relevant to content' }
          ])
        }
      ],
      model: 'claude-sonnet-4-6',
      stop_reason: 'end_turn',
      usage: { input_tokens: 100, output_tokens: 50 }
    }.to_json
  end

  before do
    allow(Leva::Prompt).to receive(:find_by).with(name: agent_name).and_return(
      instance_double(Leva::Prompt, system_prompt: instructions)
    )

    stub_request(:post, %r{api\.anthropic\.com})
      .to_return(status: 200, body: llm_response_body, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#call' do
    it 'returns an array of candidate metric hashes' do
      result = extractor.call
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
    end

    it 'returns metrics with name and description keys' do
      result = extractor.call
      expect(result.first).to include('name' => 'classification_accuracy', 'description' => a_kind_of(String))
    end

    it 'does not persist any metrics' do
      expect { extractor.call }.not_to change(Evaluation::Metric, :count)
    end

    context 'when agent prompt is not found' do
      before do
        allow(Leva::Prompt).to receive(:find_by).with(name: agent_name).and_return(nil)
      end

      it 'raises an ArgumentError' do
        expect { extractor.call }.to raise_error(ArgumentError, /No prompt found/)
      end
    end
  end
end
