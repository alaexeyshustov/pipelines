module Emails
  # The provider no longer has the sync position we asked for (Gmail answers 404 for an old +historyId+), so the
  # caller must fall back to a date-window rescan.
  class HistoryExpiredError < StandardError; end
end
