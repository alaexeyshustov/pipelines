# Yahoo (IMAP) side of one Email::SyncInboxJob run. The mailbox STATUS (UIDVALIDITY, highest UID) is read once,
# by +listing+, which runs before +position+; provider message ids are "<uid_validity>:<uid>".
class Email::SyncInboxJob::YahooInbox
  def initialize
    @status = nil
    @uids = []
  end

  def cursor
    Email::SyncCursor.for(provider: Emails::YAHOO, account: Emails.account(Emails::YAHOO))
  end

  # [mode, provider message ids]
  def listing(cursor)
    @status = Emails.inbox_status(Emails::YAHOO)
    mode, @uids = uids(cursor)
    [ mode, @uids.map { |uid| "#{uid_validity}:#{uid}" } ]
  end

  # The cursor attributes after a run in +mode+: an incremental run stops at the highest listed UID, a backfill or
  # rescan at the mailbox's highest UID, so an empty date window still leaves a UID to continue from.
  def position(mode)
    { uid_validity:, last_uid: mode == "incremental" ? @uids.max : status.last_uid }
  end

  private

  def uids(cursor)
    cursor_validity = cursor.uid_validity
    return [ "backfill", window_uids ] if cursor_validity.nil?
    return [ "rescan", window_uids ] if cursor_validity != uid_validity

    [ "incremental", Emails.inbox_uids_after(Emails::YAHOO, cursor.last_uid.to_i) ]
  end

  def window_uids
    Emails.inbox_uids_since(Emails::YAHOO, Date.current - Email.backfill_days)
  end

  def uid_validity
    status.uid_validity
  end

  def status
    @status or raise "#{self.class}#listing must run before the cursor position is read"
  end
end
