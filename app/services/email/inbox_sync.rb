# Pulls INBOX mail of one provider into +Email+ rows (ADR 0013, ADR 0018). "gmail" and "yahoo" (Emails::PROVIDER_NAMES)
# are supported; another provider adds an inbox class (cursor, listing, position; see GmailInbox) and an INBOXES entry.
#
# Cursor or window. +date_from+ and +date_to+ are Dates or nil (the caller validates them). With W the day before the
# cursor's last_synced_at (nil when the cursor is not +usable?+):
#
#   open_end = date_to.nil? || date_to >= today          # date_to = today counts as open-ended
#   from     = date_from || W || today - Email.backfill_days
#
#   open_end, usable cursor, date_from nil or >= W  -> "incremental" (Gmail history since the historyId, IMAP UIDs
#                                                      above last_uid); mail received before date_from is kept.
#                                                      Gmail 404 / a new UIDVALIDITY -> "rescan_window" [W, now]
#   open_end otherwise                              -> "window" [from, now]
#   date_to in the past                             -> "historical" [from, date_to]
#
# Bounds are Times in the app time zone (start of +from+, start of the day after +date_to+); the adapters format them.
#
# Cursor writes. Incremental advances the cursor. An open window or a rescan resets it to the current position: it
# only runs when the window reaches back to W or the cursor has no usable position, so no gap is left unread.
# Historical writes nothing, not even +failed_runs+. Gmail's profile historyId and IMAP's STATUS are read before
# listing and written only after the whole batch is stored, so mail arriving during the run is read next time.
#
# Emails already stored (unique on provider + provider_message_id) are counted as duplicates; a message that cannot
# be fetched or stored is logged, counted as failed and skipped, and holds the cursor: with any failed message the
# cursor is neither advanced nor reset, so the next run re-reads the same range (the stored messages are cheap
# duplicates). Each such run is counted on the cursor (Email::SyncCursor#failed_runs); at the
# Email::SyncCursor::MAX_FAILED_RUNS-th the cursor moves on anyway and the ids of the failed messages are logged at
# warn level, so a permanently failing message cannot hold the cursor forever. A cursor without a position yet (first
# window) is still saved to keep that count.
#
# Every stored or skipped message beats Orchestration::Heartbeat, so a long window keeps the pipeline run alive.
#
# Returns a Result: the mode, the counts for the ActionRun output and the ids of the newly stored emails. An error
# after the mode is known (anything but Emails::NotConfigured) is raised as a Failure carrying that mode.
class Email::InboxSync
  Result = Data.define(:mode, :counts, :email_ids)

  # The error of a run that got as far as picking a mode; the cause is the original error.
  class Failure < StandardError
    attr_reader :mode

    def initialize(error, mode)
      super("#{error.class}: #{error.message}")
      @mode = mode
    end
  end

  # Gmail side of one run. The profile (mailbox address and historyId) is read once, before listing.
  class GmailInbox
    def initialize
      @profile = Emails.profile(Emails::GMAIL)
    end

    def cursor
      Email::SyncCursor.for(provider: Emails::GMAIL, account: @profile.fetch(:email_address))
    end

    # Ids added since the cursor's historyId. Raises Emails::HistoryExpiredError when Gmail dropped that history.
    def incremental_ids(cursor)
      Emails.inbox_message_ids_since(Emails::GMAIL, cursor.history_id.to_s)
    end

    def window_ids(from, before)
      Emails.inbox_message_ids_after(Emails::GMAIL, from, before:)
    end

    # The cursor attributes after a run in +mode+.
    def position(_mode)
      { history_id: @profile.fetch(:history_id) }
    end
  end

  # Yahoo (IMAP) side of one run: the cursor account is the login name, provider message ids are
  # "<uid_validity>:<uid>". The mailbox STATUS (UIDVALIDITY, highest UID) is read once, before listing.
  class YahooInbox
    def initialize
      @status = nil
      @uids = Array.new
    end

    def cursor
      Email::SyncCursor.for(provider: Emails::YAHOO, account: Emails.account(Emails::YAHOO))
    end

    # Ids of the UIDs above the cursor's last_uid. Raises Emails::HistoryExpiredError when UIDVALIDITY changed, which
    # makes the old UIDs meaningless.
    def incremental_ids(cursor)
      read_status
      raise Emails::HistoryExpiredError, "UIDVALIDITY changed" if cursor.uid_validity != uid_validity

      ids_for(Emails.inbox_uids_after(Emails::YAHOO, cursor.last_uid.to_i))
    end

    def window_ids(from, before)
      read_status
      ids_for(Emails.inbox_uids_since(Emails::YAHOO, from, before:))
    end

    # The cursor attributes after a run in +mode+: an incremental run stops at the highest listed UID, a window or
    # rescan at the mailbox's highest UID, so an empty window still leaves a UID to continue from.
    def position(mode)
      { uid_validity:, last_uid: mode == "incremental" ? @uids.max : status.last_uid }
    end

    private

    def ids_for(uids)
      @uids = uids
      uids.map { |uid| "#{uid_validity}:#{uid}" }
    end

    def read_status
      @status ||= Emails.inbox_status(Emails::YAHOO)
    end

    def uid_validity
      status.uid_validity
    end

    def status
      @status or raise "#{self.class} must read the mailbox status before listing"
    end
  end

  INBOXES = { Emails::GMAIL => GmailInbox, Emails::YAHOO => YahooInbox }.freeze

  def self.call(provider:, date_from:, date_to:)
    new(provider:, date_from:, date_to:).call
  end

  def initialize(provider:, date_from:, date_to:)
    @provider = provider
    @date_from = date_from
    @date_to = date_to
    @mode = nil
  end

  def call
    inbox = INBOXES.fetch(@provider) { raise ArgumentError, "Unsupported email provider: #{@provider}" }.new
    cursor = inbox.cursor
    run(inbox, cursor)
  rescue Emails::NotConfigured
    raise
  rescue StandardError => error
    mode = @mode
    raise Failure.new(error, mode), cause: error if mode

    raise
  end

  private

  def run(inbox, cursor)
    mode, ids = list(inbox, cursor)

    result, failed_ids = store_all(mode, ids)
    return result if mode == "historical" || hold_cursor?(cursor, failed_ids)

    position = inbox.position(mode) #: Email::SyncCursor::position
    # steep cannot type a double splat of a record
    mode == "incremental" ? cursor.advance!(**position) : cursor.reset!(**position)
    result
  end

  def today
    Date.current
  end

  def open_end?
    date_to = @date_to
    date_to.nil? || date_to >= today
  end

  # W: the day before the cursor's last sync, when the cursor has a position to continue from.
  def window_start(cursor)
    cursor.last_synced_at.in_time_zone.to_date - 1 if cursor.usable? # steep:ignore
  end

  # [mode, provider message ids]
  def list(inbox, cursor)
    w = window_start(cursor)
    from = @date_from || w || (today - Email.backfill_days)
    return window(inbox, "historical", from, (@date_to.to_date + 1).beginning_of_day) unless open_end? # steep:ignore
    return window(inbox, "window", from) unless w && incremental?(w)

    incremental(inbox, cursor, w)
  end

  # An open-ended run continues from the cursor unless +date_from+ reaches back before W.
  def incremental?(window_start)
    date_from = @date_from
    date_from.nil? || date_from >= window_start
  end

  # Falls back to a window [W, now] when the provider no longer has the position (Gmail 404, new UIDVALIDITY).
  def incremental(inbox, cursor, window_start)
    @mode = "incremental"
    [ "incremental", inbox.incremental_ids(cursor) ]
  rescue Emails::HistoryExpiredError
    window(inbox, "rescan_window", window_start)
  end

  def window(inbox, mode, from, before = nil)
    @mode = mode
    [ mode, inbox.window_ids(from.beginning_of_day, before) ]
  end

  # True when a failed message keeps the cursor where it is: counts the failed run, and gives up (false, with a
  # warning) once it was the MAX_FAILED_RUNS-th, so the caller advances or resets the cursor, which clears the count.
  def hold_cursor?(cursor, failed_ids)
    return false if failed_ids.empty?

    cursor.failed_runs += 1
    if cursor.failed_runs >= Email::SyncCursor::MAX_FAILED_RUNS
      Rails.logger.warn("#{@provider} sync moves the cursor past #{cursor.failed_runs} failed runs; failed messages: #{failed_ids.join(', ')}")
      return false
    end

    cursor.save!
    true
  end

  # [Result, ids of the messages that failed]
  def store_all(mode, ids)
    known = Email.where(provider: @provider, provider_message_id: ids).pluck(:provider_message_id).to_set
    outcomes = ids.map do |message_id|
      Orchestration::Heartbeat.beat
      outcome, email = store(message_id, known)
      [ message_id, outcome, email ] # : [String, String, Email?]
    end
    failed_ids = outcomes.select { |(_id, outcome, _email)| outcome == "failed" }.map(&:first)
    email_ids = outcomes.filter_map { |(_id, _outcome, email)| email&.id }
    [ Result.new(mode:, counts: counts_for(mode, ids.size, outcomes), email_ids:), failed_ids ]
  end

  def counts_for(mode, fetched, outcomes)
    { "mode" => mode, "fetched" => fetched, "stored" => 0, "duplicates" => 0, "failed" => 0 }
      .merge(outcomes.map { |(_id, outcome, _email)| outcome }.tally)
  end

  # [counts key, new Email or nil]
  def store(message_id, known)
    return [ "duplicates", nil ] if known.include?(message_id)

    [ "stored", Email.create!(attributes_for(Emails.fetch_message(@provider, message_id))) ]
  rescue ActiveRecord::RecordNotUnique
    [ "duplicates", nil ]
  rescue StandardError => error
    Rails.logger.error("Email #{@provider}/#{message_id} failed: #{error.class}: #{error.message}")
    [ "failed", nil ]
  end

  def attributes_for(message)
    {
      provider: @provider, provider_message_id: message.fetch(:id), from_address: message.fetch(:from),
      to_address: message.fetch(:to), subject: message.fetch(:subject), date: message.fetch(:date),
      body: message.fetch(:body), html_body: message.fetch(:html_body), source_url: message.fetch(:source_url)
    }
  end
end
