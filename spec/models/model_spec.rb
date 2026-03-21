require 'rails_helper'

RSpec.describe Model, type: :model do
  it 'can be persisted' do
    model = create(:model)
    expect(model).to be_persisted
  end

  it 'stores model_id, name, and provider' do
    model = create(:model, model_id: 'mistral-7b', name: 'Mistral 7B', provider: 'mistral')
    expect(model.model_id).to eq('mistral-7b')
    expect(model.name).to eq('Mistral 7B')
    expect(model.provider).to eq('mistral')
  end

  it 'has many chats' do
    model = create(:model)
    chat  = create(:chat, model: model)
    expect(model.chats).to include(chat)
  end
end
