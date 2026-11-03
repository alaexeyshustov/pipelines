# A fetched INBOX email with its full body. +emails_fts+ (FTS5, external content) is kept in sync by DB triggers.
class Email < ApplicationRecord
  PROVIDERS = %w[gmail yahoo].freeze
  DEFAULT_BACKFILL_DAYS = 90

  include Taggable
  include FtsSearchable

  validates :provider, inclusion: { in: PROVIDERS }
  validates :provider_message_id, :from_address, :date, presence: true
  validates :provider_message_id, uniqueness: { scope: :provider }

  # How far back the first sync of a mailbox (or a rescan) looks: Setting "email_backfill_days", then
  # ENV EMAIL_BACKFILL_DAYS, then 90.
  def self.backfill_days
    Integer(Setting.fetch("email_backfill_days") || ENV.fetch("EMAIL_BACKFILL_DAYS", DEFAULT_BACKFILL_DAYS))
  end
end
