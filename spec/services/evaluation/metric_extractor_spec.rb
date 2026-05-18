require 'rails_helper'

RSpec.describe Evaluation::MetricExtractor do
  subject(:extractor) { described_class.new(agent_name) }

  let(:agent_name) { 'Emails::ClassifyAgent' }
  let(:instructions) { 'You are an email classifier. Classify emails by subject.' }
  let(:metrics_json) do
    JSON.generate([
      { 'name' => 'classification_accuracy', 'description' => 'Measures how accurately emails are classified' },
      { 'name' => 'tag_relevance', 'description' => 'Evaluates whether suggested tags are relevant to content' }
    ])
  end
  let(:llm_response_body) do
    {
      id: 'cmpl-test',
      object: 'chat.completion',
      model: 'gpt-5.4',
      choices: [ { index: 0, message: { role: 'assistant', content: metrics_json }, finish_reason: 'stop' } ],
      usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 }
    }.to_json
  end
  let(:prompt_double) { instance_double(Evaluation::Prompt, system_prompt: instructions) }
  let(:prompt_relation) { instance_double(ActiveRecord::Relation) }

  before do
    allow(Evaluation::Prompt).to receive(:where).with(name: agent_name).and_return(prompt_relation)
    allow(prompt_relation).to receive(:order).with(version: :desc, id: :desc).and_return(prompt_relation)
    allow(prompt_relation).to receive(:first).and_return(prompt_double)

    stub_request(:post, %r{api\.openai\.com})
      .to_return(status: 200, body: llm_response_body, headers: { 'Content-Type' => 'application/json' })
  end

  describe '.call' do
    it 'delegates to a new instance' do
      result = described_class.call(agent_name)
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
    end
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

    it 'sends the system prompt and agent instructions to the LLM' do
      extractor.call
      expect(WebMock).to have_requested(:post, %r{api\.openai\.com}).with { |req|
        body = JSON.parse(req.body)
        messages = body["messages"]
        messages.any? { |m| m["content"].to_s.include?("evaluation expert") } &&
          messages.any? { |m| m["content"].to_s.include?(instructions) }
      }
    end

    context 'when agent prompt is not found' do
      before do
        allow(prompt_relation).to receive(:first).and_return(nil)
      end

      it 'raises an ArgumentError' do
        expect { extractor.call }.to raise_error(ArgumentError, /No prompt found/)
      end
    end

    context 'when LLM returns invalid JSON' do
      let(:llm_response_body) do
        {
          id: 'cmpl-test', object: 'chat.completion',
          model: 'gpt-5.4',
          choices: [ { index: 0, message: { role: 'assistant', content: 'not json at all' }, finish_reason: 'stop' } ],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json
      end

      it 'raises an ArgumentError with context' do
        expect { extractor.call }.to raise_error(ArgumentError, /invalid JSON.*#{agent_name}/i)
      end
    end

    context 'when LLM returns non-array JSON' do
      let(:llm_response_body) do
        {
          id: 'cmpl-test', object: 'chat.completion',
          model: 'gpt-5.4',
          choices: [ { index: 0, message: { role: 'assistant', content: '{"key":"value"}' }, finish_reason: 'stop' } ],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json
      end

      it 'raises an ArgumentError' do
        expect { extractor.call }.to raise_error(ArgumentError, /non-array/)
      end
    end

    context 'when LLM returns metrics missing required keys' do
      let(:llm_response_body) do
        {
          id: 'cmpl-test', object: 'chat.completion',
          model: 'gpt-5.4',
          choices: [ { index: 0, message: { role: 'assistant', content: JSON.generate([ { 'name' => 'foo' } ]) }, finish_reason: 'stop' } ],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json
      end

      it 'raises an ArgumentError' do
        expect { extractor.call }.to raise_error(ArgumentError, /Invalid metric at index 0/)
      end
    end
  end

  describe '#initialize' do
    it 'raises ArgumentError for blank agent_name' do
      expect { described_class.new('') }.to raise_error(ArgumentError, /agent_name must not be blank/)
    end

    it 'raises ArgumentError for nil agent_name' do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, /agent_name must not be blank/)
    end
  end
end
