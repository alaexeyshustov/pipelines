# GH #236: Yahoo emails move from the bare IMAP UID to "<uid_validity>:<uid>". The current UIDVALIDITY can only be
# read from IMAP, which a migration must not depend on (CI, fresh databases, no credentials): without Yahoo
# credentials or when IMAP fails this is a no-op and the same fix is available as `bin/rails emails:rewrite_yahoo_ids`.
class RewriteYahooProviderMessageIds < ActiveRecord::Migration[8.1]
  def up
    changed = Email::YahooIdRewriter.rewrite_from_env
    say(changed.nil? ? "No Yahoo credentials: run `bin/rails emails:rewrite_yahoo_ids` later" : "Rewrote #{changed} Yahoo ids")
  rescue StandardError => error
    say("Yahoo id rewrite skipped (#{error.class}: #{error.message}); run `bin/rails emails:rewrite_yahoo_ids` later")
  end

  def down; end
end
