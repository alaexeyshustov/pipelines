# Gmail side of one Email::SyncInboxJob run. The profile (mailbox address and historyId) is read once, before
# listing, so the historyId written to the cursor never skips mail that arrived during the run.
class Email::SyncInboxJob::GmailInbox
  def initialize
    @profile = Emails.profile(Emails::GMAIL)
  end

  def cursor
    Email::SyncCursor.for(provider: Emails::GMAIL, account: @profile.fetch(:email_address))
  end

  # [mode, provider message ids]
  def listing(cursor)
    history_id = cursor.history_id
    return [ "backfill", window_ids ] if history_id.blank?

    [ "incremental", Emails.inbox_message_ids_since(Emails::GMAIL, history_id.to_s) ]
  rescue Emails::HistoryExpiredError
    [ "rescan", window_ids ]
  end

  # The cursor attributes after a run in +mode+.
  def position(_mode)
    { history_id: @profile.fetch(:history_id) }
  end

  private

  def window_ids
    Emails.inbox_message_ids_after(Emails::GMAIL, Date.current - Email.backfill_days)
  end
end
