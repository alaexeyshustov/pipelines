FactoryBot.define do
  factory :tool_call do
    sequence(:tool_call_id) { |n| "call_#{n}" }
    name { 'list_emails' }
    association :message
  end
end
