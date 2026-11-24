module Orchestration
  module Executors
    # Step 3 of the Email Ingestion pipeline (ADR 0018): embeds the tagged emails among the ids that have no embedding
    # for the current model yet, one Embeddings::Embed call per email. Emails that are not tagged are listed as
    # skipped (only tagged emails are embedded), and so are tagged ones without embeddable text. An email that already
    # has an embedding appears in no list.
    class EmailsEmbed
      include Orchestration::Executable
      include PerRecord

      input_schema(email_ids: PerRecord::ID_LIST)
      output_schema(embedded: PerRecord::ID_LIST, skipped: PerRecord::ID_LIST, failed: PerRecord::FAILED_LIST)

      def self.call(email_ids:, **_kwargs)
        new(email_ids:).execute
      end

      def initialize(email_ids:, **_kwargs)
        @email_ids = email_ids
      end

      def execute
        embedded = Array.new # : Array[Integer]
        failed = Array.new # : Array[json_object]
        skipped = Email.where(id: @email_ids).where.not(classification_status: "tagged").ids
        each_record(unembedded, @email_ids, failed) do |email|
          (Embeddings::Embed.call([ email ]).embedded.positive? ? embedded : skipped) << email.id
        end
        { "embedded" => embedded, "skipped" => skipped, "failed" => failed }
      end

      private

      def unembedded
        Email.without_embedding(model: LlmModels.embedding).where(classification_status: "tagged")
      end
    end
  end
end
