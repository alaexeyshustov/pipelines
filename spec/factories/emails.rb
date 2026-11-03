FactoryBot.define do
  factory :email do
    provider { "gmail" }
    sequence(:provider_message_id) { |n| "msg_#{n}" }
    from_address { "recruiter@acme.com" }
    to_address { "me@example.com" }
    subject { "Your application" }
    date { Time.zone.now }
    body { "Thanks for applying." }
    html_body { nil }
    source_url { nil }
  end
end
