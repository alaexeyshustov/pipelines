FactoryBot.define do
  factory :tag do
    sequence(:name) { |n| "tag_#{n}" }
  end

  factory :subtag do
    tag
    sequence(:name) { |n| "subtag_#{n}" }
  end

  factory :tagging do
    association :taggable, factory: :application_mail
    tag
    source { "manual" }
  end
end
