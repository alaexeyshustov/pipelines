# YahooAdapter is too long

**Status:** draft

**Source:** `lib/emails/adapters/yahoo_adapter.rb`

`Emails::Adapters::YahooAdapter` bundles IMAP connection management, message listing, body extraction, label handling, and MIME parsing in one class, requiring a `rubocop:disable Metrics/ClassLength` suppression.

**Suggested approach:** follow the same decomposition path as `GmailAdapter` — extract connection, parsing, and label concerns into dedicated objects so the adapter stays focused on IMAP transport.
