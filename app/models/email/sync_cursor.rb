# Where the last sync of one mailbox stopped (see ADR 0013). Gmail keeps a +history_id+; IMAP keeps
# +uid_validity+ + +last_uid+. One row per provider, account and mailbox.
#
# +failed_runs+ counts the consecutive runs that had failed messages: such a run holds the cursor, and once it has
# happened MAX_FAILED_RUNS times the sync moves the cursor on anyway, so a permanently failing message cannot hold it
# forever. The count is cleared whenever the position moves (advance!/reset!).
class Email::SyncCursor < ApplicationRecord
  self.table_name = "email_sync_cursors"

  DEFAULT_MAILBOX = "INBOX".freeze
  MAX_FAILED_RUNS = 3

  validates :provider, inclusion: { in: Email::PROVIDERS }
  validates :account, :mailbox, presence: true
  validates :account, uniqueness: { scope: %i[provider mailbox] }

  # Finds the cursor of a mailbox, or builds an unsaved one (no cursor means "backfill").
  def self.for(provider:, account:, mailbox: DEFAULT_MAILBOX)
    find_or_initialize_by(provider: provider, account: account, mailbox: mailbox)
  end

  # Moves the position forward only and stamps +last_synced_at+. The comparison runs on the row as it is now, under
  # a write lock (the row is reloaded first, discarding unsaved changes), so a stale or overlapping run cannot rewind it.
  def advance!(history_id: nil, uid_validity: nil, last_uid: nil)
    with_current_row do
      self.history_id = history_id if history_id && newer_history_id?(history_id)
      self.uid_validity = uid_validity if uid_validity
      self.last_uid = last_uid if last_uid && newer_uid?(last_uid)
      self.last_synced_at = Time.current
      self.failed_runs = 0
      save!
    end
  end

  # Replaces the position (possibly empty, or of a new UIDVALIDITY) after a rescan and stamps +last_rescan_at+. A
  # position older than the stored one within the same epoch (a run that read the row before another advanced it)
  # is not applied: the stored one stays.
  def reset!(history_id: nil, uid_validity: nil, last_uid: nil)
    with_current_row do
      now = Time.current
      self.last_synced_at = now
      self.last_rescan_at = now
      self.failed_runs = 0
      assign_attributes(history_id:, uid_validity:, last_uid:) unless rewinds?(history_id, uid_validity, last_uid)
      save!
    end
  end

  private

  def with_current_row(&)
    transaction do
      reload(lock: true) if persisted?
      yield
    end
  end

  def rewinds?(candidate_history_id, candidate_uid_validity, candidate_last_uid)
    older_history?(candidate_history_id) || older_uid?(candidate_uid_validity, candidate_last_uid)
  end

  def older_history?(candidate)
    !candidate.nil? && !history_id.nil? && candidate.to_i < history_id.to_i
  end

  def older_uid?(candidate_uid_validity, candidate)
    return false if candidate.nil? || last_uid.nil?

    candidate_uid_validity == uid_validity && candidate < last_uid
  end

  def newer_history_id?(candidate)
    current = self.history_id
    current.nil? || candidate.to_i > current.to_i
  end

  def newer_uid?(candidate)
    current = last_uid
    current.nil? || candidate > current || (uid_validity_changed? && !uid_validity_was.nil?)
  end
end
