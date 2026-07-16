FactoryBot.define do
  factory :chat do
    model_id { create(:model)&.id }
  end
end
