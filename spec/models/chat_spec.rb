require 'rails_helper'

RSpec.describe Chat, type: :model do
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

  it 'does not require a model' do
    chat = build(:chat, model: nil)
    expect(chat).to be_valid
  end
end
