FactoryBot.define do
  factory :email_sync_cursor, class: "Email::SyncCursor" do
    provider { "gmail" }
    sequence(:account) { |n| "user#{n}@example.com" }
    mailbox { "INBOX" }
  end
end
