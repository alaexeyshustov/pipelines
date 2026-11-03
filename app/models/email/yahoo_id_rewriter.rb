# One-off data fix for GH #236: Yahoo emails used to be stored under the bare IMAP UID; they are now
# "<uid_validity>:<uid>". Idempotent: only ids without a ":" are touched, and a row whose target id already exists
# is skipped. The migration and the +emails:rewrite_yahoo_ids+ rake task both call it.
class Email::YahooIdRewriter
  # Rewrites bare Yahoo ids using +uid_validity+; returns the number of rows changed.
  def self.rewrite(uid_validity)
    changed = 0
    Email.where(provider: "yahoo").where.not("provider_message_id LIKE ?", "%:%").find_each do |email|
      new_id = "#{uid_validity}:#{email.provider_message_id}"
      next if Email.exists?(provider: "yahoo", provider_message_id: new_id)

      email.update!(provider_message_id: new_id)
      changed += 1
    end
    changed
  end

  # Rewrites with the current INBOX UIDVALIDITY of the configured Yahoo account; nil when there are no
  # credentials (nothing can be rewritten without knowing the UIDVALIDITY).
  def self.rewrite_from_env
    adapter = Emails::Adapters::YahooAdapter.from_env
    begin
      rewrite(adapter.inbox_uid_validity)
    ensure
      adapter.on_exit
    end
  rescue RuntimeError => error
    raise unless error.message.start_with?("Missing Yahoo credentials")

    nil
  end
end
