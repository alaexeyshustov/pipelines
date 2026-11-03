# A fetched INBOX email with its full body. +emails_fts+ (FTS5, external content) is kept in sync by DB triggers.
class Email < ApplicationRecord
  PROVIDERS = %w[gmail yahoo].freeze

  include Taggable
  include FtsSearchable

  validates :provider, inclusion: { in: PROVIDERS }
  validates :provider_message_id, :from_address, :date, presence: true
  validates :provider_message_id, uniqueness: { scope: :provider }
end
