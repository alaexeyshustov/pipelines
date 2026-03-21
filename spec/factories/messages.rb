FactoryBot.define do
  factory :message do
    role    { 'user' }
    content { 'Hello' }
    association :chat
  end
end
