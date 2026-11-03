# Pulls new INBOX mail of one provider into +Email+ rows (ADR 0013). Only "gmail" is supported so far; another
# provider adds a +sync_<provider>+ method and a branch in +perform+.
#
# Gmail: the cursor account is the mailbox address from the Gmail profile. With no cursor the last
# Email.backfill_days days are listed ("backfill"); with a cursor the history since its historyId is read
# ("incremental"); if Gmail no longer has that history (404) the same date window is rescanned ("rescan"). The
# profile historyId is captured before listing and written to the cursor only after the whole batch is stored, so a
# failed run re-reads instead of skipping; a provider error raises and leaves the cursor untouched.
#
# Emails already stored (unique on provider + provider_message_id) are counted as duplicates; a message that cannot
# be fetched or stored is logged, counted as failed and skipped. Returns a Result: the counts for the StepRun
# output and the ids of the newly stored emails, for the caller to enqueue their processing.
class Email::SyncInboxJob < ApplicationJob
  Result = Data.define(:counts, :email_ids)

  def perform(provider)
    case provider
    when "gmail" then sync_gmail
    else raise ArgumentError, "Unsupported email provider: #{provider}"
    end
  end

  private

  def sync_gmail
    profile = Emails.profile("gmail")
    cursor = Email::SyncCursor.for(provider: "gmail", account: profile.fetch(:email_address))
    mode, ids = gmail_message_ids(cursor)

    result = store_all("gmail", mode, ids)
    mode == "incremental" ? cursor.advance!(history_id: profile.fetch(:history_id)) : cursor.reset!(history_id: profile.fetch(:history_id))
    result
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
