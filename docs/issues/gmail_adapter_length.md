# GmailAdapter is too long

**Status:** draft

**Source:** `lib/emails/adapters/gmail_adapter.rb`

`Emails::Adapters::GmailAdapter` wraps the Gmail API and handles auth, message listing, fetching, label management, and MIME parsing in a single class. The scope requires a `rubocop:disable Metrics/ClassLength` suppression.

**Suggested approach:** extract orthogonal concerns — auth/credential setup, label management, MIME parsing — into focused collaborators, keeping the adapter itself responsible only for transport-level operations.
