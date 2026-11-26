module Emails
  module Adapters
    # One mailbox read from a JSON file instead of Gmail or IMAP, for e2e runs and offline development
    # (EMAIL_FIXTURES=<path>, see Emails.use_fixtures). Implements only the readers Email::InboxSync and
    # Document::IngestEmailAttachments call; it never changes and never reports new history, so an incremental
    # sync finds nothing. Message ids are the fixture's "id" for Gmail and "<uid_validity>:<uid>" for Yahoo.
    #
    #   { "gmail": { "account": "me@gmail.test", "history_id": "100", "messages": [
    #       { "id": "g1", "from": "...", "to": "...", "subject": "...", "date": "2026-11-02T09:00:00Z",
    #         "body": "...", "html_body": null,
    #         "attachments": [{ "id": "a1", "filename": "cv.txt", "mime_type": "text/plain", "data": "..." }] }] },
    #     "yahoo": { "account": "me@yahoo.test", "uid_validity": 1, "messages": [{ "uid": 1, ... }] } }
    class FixtureAdapter < BaseAdapter
      Message = Data.define(:id, :uid, :from, :to, :subject, :date, :body, :html_body, :attachments)
      Attachment = Data.define(:id, :filename, :mime_type, :data)

      def self.from_env(opts = {})
        provider = opts.fetch(:provider).to_s
        fixtures = JSON.parse(File.read(opts.fetch(:path).to_s)) # : Hash[String, Hash[String, json_object_value]]
        new(provider:, mailbox: fixtures.fetch(provider))
      end

      def initialize(provider:, mailbox:)
        @provider = provider
        @account = mailbox.fetch("account").to_s
        @history_id = mailbox.fetch("history_id", "1").to_s
        @uid_validity = mailbox.fetch("uid_validity", 1).to_s.to_i
        messages = mailbox.fetch("messages") # : Array[json_object]
        @messages = messages.map { |message| build_message(message) }.index_by { |message| message_id(message) }
      end

      attr_reader :account

      def profile
        { email_address: account, history_id: @history_id }
      end

      def inbox_message_ids_since(_history_id) = []

      def inbox_message_ids_after(from, before: nil)
        received(from, before).map { |message| message_id(message) }
      end

      def inbox_status
        ImapInboxReader::Status.new(uid_validity: @uid_validity, last_uid: uids.max || 0)
      end

      def inbox_uids_after(last_uid)
        uids.select { |uid| uid > last_uid }.sort
      end

      def inbox_uids_since(from, before: nil)
        received(from, before).map(&:uid).sort
      end

      def fetch_message(message_id)
        message = find(message_id)
        {
          id: message_id(message), provider: @provider, subject: message.subject, from: message.from, to: message.to,
          date: message.date, body: message.body, html_body: message.html_body, source_url: nil, thread_id: nil,
          labels: [ "INBOX" ]
        }
      end

      def attachments(message_id)
        find(message_id).attachments.map do |attachment|
          { id: attachment.id, filename: attachment.filename, mime_type: attachment.mime_type, size: attachment.data.bytesize }
        end
      end

      def attachment(message_id, attachment_id)
        found = find(message_id).attachments.find { |attachment| attachment.id == attachment_id }
        found ? found.data : raise("Attachment not found: #{attachment_id}")
      end

      private

      def build_message(message)
        Message.new(
          id: message["id"].to_s, uid: message["uid"].to_s.to_i, from: text(message, "from"), to: text(message, "to"),
          subject: text(message, "subject"), date: Time.iso8601(text(message, "date")).utc, body: text(message, "body"),
          html_body: message["html_body"]&.to_s, attachments: build_attachments(message)
        )
      end

      def build_attachments(message)
        attachments = message.fetch("attachments", []) # : Array[json_object]
        attachments.map do |attachment|
          Attachment.new(
            id: text(attachment, "id"), filename: text(attachment, "filename"), mime_type: text(attachment, "mime_type"),
            data: text(attachment, "data")
          )
        end
      end

      def text(fixture, key)
        fixture.fetch(key).to_s
      end

      def message_id(message)
        @provider == Emails::YAHOO ? "#{@uid_validity}:#{message.uid}" : message.id
      end

      def uids
        @messages.values.map(&:uid)
      end

      def find(message_id)
        @messages.fetch(message_id.to_s) { raise "Message not found: #{message_id}" }
      end

      def received(from, before)
        @messages.values.select { |message| message.date >= from.to_time && (before.nil? || message.date < before.to_time) }
      end
    end
  end
end
