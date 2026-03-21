FactoryBot.define do
  factory :application_mail do
    date     { Date.today }
    provider { 'gmail' }
    sequence(:email_id) { |n| "email_#{n}@gmail.com" }
    company  { 'Acme Corp' }
    job_title { 'Software Engineer' }
    action   { 'applied' }
  end
end
