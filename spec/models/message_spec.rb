require 'rails_helper'

RSpec.describe Message do
  it 'belongs to a chat' do
    chat    = create(:chat)
    message = create(:message, chat: chat)
    expect(message.chat).to eq(chat)
  end
end
