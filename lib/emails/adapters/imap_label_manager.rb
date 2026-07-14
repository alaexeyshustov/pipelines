module Emails
  module Adapters
    class ImapLabelManager
      def initialize(session:)
        @session = session
      end

      def create_label(name:)
        @session.with_lock { @session.imap.create(name) }
        { id: name, name: name, type: "user" }
      rescue Net::IMAP::NoResponseError => error
        raise error unless error.message.include?("CREATE failed - Mailbox exists")

        { id: name, name: name, type: "user" }
      end

      def add_labels(uid, add, source_mailbox)
        @session.with_lock { apply_add_labels(uid, add, source_mailbox) }
      end

      def remove_labels(uid, remove, source_mailbox)
        remove.each { |label| remove_label(uid, label, source_mailbox) }
      end

      private

      def apply_add_labels(uid, add, source_mailbox)
        @session.ensure_mailbox(source_mailbox)
        add.each do |label|
          if imap_flag?(label)
            @session.imap.uid_store(uid, "+FLAGS", [ label ])
          else
            @session.imap.uid_copy(uid, label)
          end
        end
      end

      def remove_label(uid, label, source_mailbox)
        @session.with_lock { apply_remove_label(uid, label, source_mailbox) }
      end

      def apply_remove_label(uid, label, source_mailbox)
        if imap_flag?(label)
          @session.ensure_mailbox(source_mailbox)
          @session.imap.uid_store(uid, "-FLAGS", [ label ])
        else
          @session.ensure_mailbox(label)
          @session.imap.uid_store(uid, "+FLAGS", [ :Deleted ])
          @session.imap.expunge
        end
      end

      def imap_flag?(label)
        label.start_with?("\\")
      end
    end
  end
end
