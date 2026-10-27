require 'rails_helper'

RSpec.describe Chat do
  it 'has many messages' do
    chat = create(:chat)
    message = create(:message, chat: chat)
    expect(chat.messages).to include(message)
  end

  it 'optionally belongs to a model' do
    model = RubyLLM::ActiveRecord::Model.create!(model_id: 'mistral-7b', name: 'Mistral 7B', provider: 'mistral')
    chat  = create(:chat, model: model)
    expect(chat.model).to eq(model)
  end
end
