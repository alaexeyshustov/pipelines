FactoryBot.define do
  factory :document do
    title { "Offer letter.pdf" }
    mime_type { "application/pdf" }
    text { "# Offer\n\nWe are pleased to offer you the position." }
    sequence(:checksum) { |n| "sha256_#{n}" }
    source { "email_attachment" }
    source_url { nil }
    source_ref { { "provider" => "gmail", "message_id" => "msg_1", "attachment_id" => "att_1" } }
  end
end
