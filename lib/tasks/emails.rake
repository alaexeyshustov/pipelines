namespace :emails do
  desc "Rewrite bare Yahoo provider_message_ids to <uid_validity>:<uid> using the current INBOX UIDVALIDITY (idempotent)"
  task rewrite_yahoo_ids: :environment do
    changed = Email::YahooIdRewriter.rewrite_from_env
    puts(changed.nil? ? "Missing Yahoo credentials (YAHOO_USERNAME, YAHOO_APP_PASSWORD)" : "Rewrote #{changed} Yahoo ids")
  end
end
