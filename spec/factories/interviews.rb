FactoryBot.define do
  factory :interview do
    company   { 'Acme Corp' }
    sequence(:job_title) { |n| "Software Engineer #{n}" }
    status    { 'pending_reply' }
    applied_at { Time.zone.today }
  end
end
