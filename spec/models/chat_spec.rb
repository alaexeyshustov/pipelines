require 'rails_helper'

RSpec.describe Chat do
  it 'can be persisted' do
    chat = create(:chat)
    expect(chat).to be_persisted
  end

  it 'has many messages' do
    chat = create(:chat)
    message = create(:message, chat: chat)
    expect(chat.messages).to include(message)
  end

  it 'optionally belongs to a model' do
    model = create(:model)
    chat  = create(:chat, model: model)
    expect(chat.model).to eq(model)
  end

  describe '#to_llm_context' do
    it 'returns a hash with messages' do
      chat = create(:chat)
      create(:message, chat: chat, role: 'user', content: 'Hello')
      expect(chat.to_llm_context).to eq({ messages: "user: Hello" })
    end
  end
end
