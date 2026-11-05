# Where the last sync of one mailbox stopped (see ADR 0013). Gmail keeps a +history_id+; IMAP keeps
# +uid_validity+ + +last_uid+. One row per provider, account and mailbox.
#
# +failed_attempts+ (provider_message_id => count) lets a sync give up on a message that keeps failing: while any
# message fails the cursor is held, and after MAX_FAILED_ATTEMPTS failed runs the sync skips that message so it no
# longer holds the cursor. The counts are dropped whenever the position moves (advance!/reset!), as the range they
# belong to is then no longer re-read.
class Email::SyncCursor < ApplicationRecord
  self.table_name = "email_sync_cursors"

  DEFAULT_MAILBOX = "INBOX".freeze
  MAX_FAILED_ATTEMPTS = 3

  validates :provider, inclusion: { in: Email::PROVIDERS }
  validates :account, :mailbox, presence: true
  validates :account, uniqueness: { scope: %i[provider mailbox] }

  # Finds the cursor of a mailbox, or builds an unsaved one (no cursor means "backfill").
  def self.for(provider:, account:, mailbox: DEFAULT_MAILBOX)
    find_or_initialize_by(provider: provider, account: account, mailbox: mailbox)
  end

  def gave_up_on?(message_id)
    failed_attempts.fetch(message_id, 0) >= MAX_FAILED_ATTEMPTS
  end

  # Counts one more failed attempt in memory; the caller saves.
  def record_failure(message_id)
    self.failed_attempts = failed_attempts.merge(message_id => failed_attempts.fetch(message_id, 0) + 1)
  end

  # Moves the position forward only (a stale or overlapping run cannot rewind it) and stamps +last_synced_at+.
  def advance!(history_id: nil, uid_validity: nil, last_uid: nil)
    self.history_id = history_id if history_id && newer_history_id?(history_id)
    self.uid_validity = uid_validity if uid_validity
    self.last_uid = last_uid if last_uid && newer_uid?(last_uid)
    self.last_synced_at = Time.current
    self.failed_attempts = {}
    save!
  end

  # Replaces the position (possibly backwards or empty) after a rescan and stamps +last_rescan_at+.
  def reset!(history_id: nil, uid_validity: nil, last_uid: nil)
    now = Time.current
    update!(history_id: history_id, uid_validity: uid_validity, last_uid: last_uid,
            last_synced_at: now, last_rescan_at: now, failed_attempts: {})
  end

  private

  def newer_history_id?(candidate)
    current = self.history_id
    current.nil? || candidate.to_i > current.to_i
  end

  def newer_uid?(candidate)
    current = last_uid
    current.nil? || candidate > current || (uid_validity_changed? && !uid_validity_was.nil?)
  end
end
