FactoryBot.define do
  factory :evaluation_wizard_draft, class: "Evaluation::WizardDraft" do
    sequence(:session_token) { |n| "token_#{n}" }
    step { 1 }
    payload { nil }
  end
end
