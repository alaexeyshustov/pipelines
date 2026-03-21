FactoryBot.define do
  factory :model do
    sequence(:model_id) { |n| "mistral-#{n}" }
    name     { 'Mistral 7B' }
    provider { 'mistral' }
    family   { 'mistral' }
  end
end
