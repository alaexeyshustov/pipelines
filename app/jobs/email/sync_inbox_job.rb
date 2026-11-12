# Pulls new INBOX mail of one provider into +Email+ rows (ADR 0013). "gmail" and "yahoo" (Emails::PROVIDER_NAMES) are supported; another
# provider adds a +sync_<provider>+ method and a branch in +perform+.
#
# Gmail: the cursor account is the mailbox address from the Gmail profile. With no cursor the last
# Email.backfill_days days are listed ("backfill"); with a cursor the history since its historyId is read
# ("incremental"); if Gmail no longer has that history (404) the same date window is rescanned ("rescan"). The
# profile historyId is captured before listing and written to the cursor only after the whole batch is stored, so a
# failed run re-reads instead of skipping; a provider error raises and leaves the cursor untouched.
#
# Yahoo (IMAP): the cursor account is the login username and the position is UIDVALIDITY + last UID. Both come from
# one STATUS call made before listing; a backfill or rescan stores the mailbox's highest UID (UIDNEXT - 1) rather than
# the highest listed one, so an empty date window cannot leave a cursor without a UID (the next incremental run would
# read UID 1:*), and mail arriving during the run is still read next time. With no cursor the last Email.backfill_days days are listed (IMAP SINCE, "backfill"); with the same
# UIDVALIDITY the UIDs above last_uid are read ("incremental"); a changed UIDVALIDITY makes old UIDs meaningless, so
# the date window is rescanned and the cursor reset ("rescan"). provider_message_id is "<uid_validity>:<uid>", so
# a new UIDVALIDITY yields new rows instead of collisions.
#
# Emails already stored (unique on provider + provider_message_id) are counted as duplicates; a message that cannot
# be fetched or stored is logged, counted as failed and skipped, and holds the cursor: with any failed message the
# cursor is neither advanced nor reset (a rescan included), so the next run re-reads the same range (the stored
# messages are cheap duplicates). Each such run is counted on the cursor (Email::SyncCursor#failed_runs); at the
# Email::SyncCursor::MAX_FAILED_RUNS-th the cursor moves on anyway, as after a clean run, and the ids of the failed
# messages are logged at warn level, so a permanently failing message cannot hold the cursor forever. A cursor that
# has no position yet (first backfill) is still saved to keep that count. Returns a Result: the counts for the
# StepRun output and the ids of the newly stored emails, for the caller to enqueue their processing.
class Email::SyncInboxJob < ApplicationJob
  Result = Data.define(:counts, :email_ids)

  def perform(provider)
    case provider
    when Emails::GMAIL then sync_gmail
    when Emails::YAHOO then sync_yahoo
    else raise ArgumentError, "Unsupported email provider: #{provider}"
    end
  end

  private

  def sync_gmail
    profile = Emails.profile(Emails::GMAIL)
    cursor = Email::SyncCursor.for(provider: Emails::GMAIL, account: profile.fetch(:email_address))
    mode, ids = gmail_message_ids(cursor)

    result, failed_ids = store_all(Emails::GMAIL, mode, ids)
    return result if hold_cursor?(Emails::GMAIL, cursor, failed_ids)

    mode == "incremental" ? cursor.advance!(history_id: profile.fetch(:history_id)) : cursor.reset!(history_id: profile.fetch(:history_id))
    result
  end

  def sync_yahoo
    cursor = Email::SyncCursor.for(provider: Emails::YAHOO, account: Emails.account(Emails::YAHOO))
    status = Emails.inbox_status(Emails::YAHOO)
    uid_validity = status.uid_validity
    mode, uids = yahoo_uids(cursor, uid_validity)

    result, failed_ids = store_all(Emails::YAHOO, mode, uids.map { |uid| "#{uid_validity}:#{uid}" })
    return result if hold_cursor?(Emails::YAHOO, cursor, failed_ids)

    save_yahoo_cursor(cursor, mode, uid_validity, mode == "incremental" ? uids.max : status.last_uid)
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

    [ "incremental", Emails.inbox_uids_after(Emails::YAHOO, cursor.last_uid.to_i) ]
  end

  def yahoo_window_uids
    Emails.inbox_uids_since(Emails::YAHOO, Date.current - Email.backfill_days)
  end

  def gmail_message_ids(cursor)
    return [ "backfill", window_ids ] if cursor.history_id.blank?

    [ "incremental", Emails.inbox_message_ids_since(Emails::GMAIL, cursor.history_id.to_s) ]
  rescue Emails::HistoryExpiredError
    [ "rescan", window_ids ]
  end

  def window_ids
    Emails.inbox_message_ids_after(Emails::GMAIL, Date.current - Email.backfill_days)
  end

  # True when a failed message keeps the cursor where it is: counts the failed run, and gives up (false, with a
  # warning) once it was the MAX_FAILED_RUNS-th, so the caller advances or resets the cursor, which clears the count.
  def hold_cursor?(provider, cursor, failed_ids)
    return false if failed_ids.empty?

    cursor.failed_runs += 1
    if cursor.failed_runs >= Email::SyncCursor::MAX_FAILED_RUNS
      Rails.logger.warn("#{provider} sync moves the cursor past #{cursor.failed_runs} failed runs; failed messages: #{failed_ids.join(', ')}")
      return false
    end

    cursor.save!
    true
  end

  # [Result, ids of the messages that failed]
  def store_all(provider, mode, ids)
    known = Email.where(provider: provider, provider_message_id: ids).pluck(:provider_message_id).to_set
    outcomes = ids.map { |message_id| [ message_id, *store(provider, message_id, known) ] }
    failed_ids = outcomes.select { |(_id, outcome, _email)| outcome == "failed" }.map(&:first)
    [ Result.new(counts: counts_for(mode, ids.size, outcomes), email_ids: outcomes.filter_map { |(*, email)| email&.id }), failed_ids ]
  end

  def counts_for(mode, fetched, outcomes)
    { "mode" => mode, "fetched" => fetched, "stored" => 0, "duplicates" => 0, "failed" => 0 }
      .merge(outcomes.map { |(_id, outcome, _email)| outcome }.tally)
  end

  # [counts key, new Email or nil]
  def store(provider, message_id, known)
    return [ "duplicates", nil ] if known.include?(message_id)

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
