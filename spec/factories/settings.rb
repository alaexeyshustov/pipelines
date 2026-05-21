FactoryBot.define do
  factory :setting do
    sequence(:key) { |n| "setting_key_#{n}" }
    value { "test-model" }
  end
end
