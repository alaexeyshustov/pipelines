# Pulls new INBOX mail of one provider into +Email+ rows (ADR 0013). "gmail" and "yahoo" are supported; another
# provider adds a +sync_<provider>+ method and a branch in +perform+.
#
# Gmail: the cursor account is the mailbox address from the Gmail profile. With no cursor the last
# Email.backfill_days days are listed ("backfill"); with a cursor the history since its historyId is read
# ("incremental"); if Gmail no longer has that history (404) the same date window is rescanned ("rescan"). The
# profile historyId is captured before listing and written to the cursor only after the whole batch is stored, so a
# failed run re-reads instead of skipping; a provider error raises and leaves the cursor untouched.
#
# Yahoo (IMAP): the cursor account is the login username and the position is UIDVALIDITY + last UID, captured before
# listing. With no cursor the last Email.backfill_days days are listed (IMAP SINCE, "backfill"); with the same
# UIDVALIDITY the UIDs above last_uid are read ("incremental"); a changed UIDVALIDITY makes old UIDs meaningless, so
# the date window is rescanned and the cursor reset ("rescan"). provider_message_id is "<uid_validity>:<uid>", so
# a new UIDVALIDITY yields new rows instead of collisions.
#
# Emails already stored (unique on provider + provider_message_id) are counted as duplicates; a message that cannot
# be fetched or stored is logged, counted as failed and skipped, and holds the cursor: with any failed message the
# cursor is neither advanced nor reset, so the next run re-reads the same range (the stored messages are cheap
# duplicates). A permanently failing message keeps the cursor until a provider history 404 triggers a rescan. Returns a Result: the counts for the StepRun
# output and the ids of the newly stored emails, for the caller to enqueue their processing.
class Email::SyncInboxJob < ApplicationJob
  Result = Data.define(:counts, :email_ids)

  def perform(provider)
    case provider
    when "gmail" then sync_gmail
    when "yahoo" then sync_yahoo
    else raise ArgumentError, "Unsupported email provider: #{provider}"
    end
  end

  private

  def sync_gmail
    profile = Emails.profile("gmail")
    cursor = Email::SyncCursor.for(provider: "gmail", account: profile.fetch(:email_address))
    mode, ids = gmail_message_ids(cursor)

    result = store_all("gmail", mode, ids)
    return result if failures?(result)

    mode == "incremental" ? cursor.advance!(history_id: profile.fetch(:history_id)) : cursor.reset!(history_id: profile.fetch(:history_id))
    result
  end

  def sync_yahoo
    cursor = Email::SyncCursor.for(provider: "yahoo", account: Emails.account("yahoo"))
    uid_validity = Emails.inbox_uid_validity("yahoo")
    mode, uids = yahoo_uids(cursor, uid_validity)

    result = store_all("yahoo", mode, uids.map { |uid| "#{uid_validity}:#{uid}" })
    return result if failures?(result)

    save_yahoo_cursor(cursor, mode, uid_validity, uids.max)
    result
  end

  def save_yahoo_cursor(cursor, mode, uid_validity, last_uid)
    if mode == "incremental"
      cursor.advance!(uid_validity: uid_validity, last_uid: last_uid)
    else
      cursor.reset!(uid_validity: uid_validity, last_uid: last_uid)
    end
  end

  def yahoo_uids(cursor, uid_validity)
    return [ "backfill", yahoo_window_uids ] if cursor.uid_validity.nil?
    return [ "rescan", yahoo_window_uids ] if cursor.uid_validity != uid_validity

    [ "incremental", Emails.inbox_uids_after("yahoo", cursor.last_uid.to_i) ]
  end

  def yahoo_window_uids
    Emails.inbox_uids_since("yahoo", Date.current - Email.backfill_days)
  end

  def gmail_message_ids(cursor)
    return [ "backfill", window_ids ] if cursor.history_id.blank?

    [ "incremental", Emails.inbox_message_ids_since("gmail", cursor.history_id.to_s) ]
  rescue Emails::HistoryExpiredError
    [ "rescan", window_ids ]
  end

  def window_ids
    Emails.inbox_message_ids_after("gmail", Date.current - Email.backfill_days)
  end

  def failures?(result)
    result.counts.fetch("failed").positive?
  end

  def store_all(provider, mode, ids)
    counts = { "mode" => mode, "fetched" => ids.size, "stored" => 0, "duplicates" => 0, "failed" => 0 }
    email_ids = []
    ids.each do |message_id|
      outcome, email = store(provider, message_id)
      counts[outcome] += 1
      email_ids << email.id if email
    end
    Result.new(counts: counts, email_ids: email_ids)
  end

  # [counts key, new Email or nil]
  def store(provider, message_id)
    return [ "duplicates", nil ] if Email.exists?(provider: provider, provider_message_id: message_id)

    [ "stored", Email.create!(attributes_for(provider, Emails.fetch_message(provider, message_id))) ]
  rescue ActiveRecord::RecordNotUnique
    [ "duplicates", nil ]
  rescue StandardError => error
    Rails.logger.error("Email #{provider}/#{message_id} failed: #{error.class}: #{error.message}")
    [ "failed", nil ]
  end

  def attributes_for(provider, message)
    {
      provider: provider, provider_message_id: message.fetch(:id), from_address: message.fetch(:from),
      to_address: message.fetch(:to), subject: message.fetch(:subject), date: message.fetch(:date),
      body: message.fetch(:body), html_body: message.fetch(:html_body), source_url: message.fetch(:source_url)
    }
  end
end
