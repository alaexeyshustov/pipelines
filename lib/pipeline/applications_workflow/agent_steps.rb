module Pipeline
  class ApplicationsWorkflow
    class AgentSteps
      def initialize(model:)
        @model = model
      end

      def classify_email(emails:)
        input = { emails: emails.map { |email| email.slice("id", "subject") } }.to_json

        Orchestration::Agents::EmailsClassifier.create.with_model(@model).ask(input).content
      end

      def filter_emails(emails:, tags:)
        tags_by_id = tags.index_by { |tag| tag["id"] }
        # steep:ignore:start
        input = {
          topic: "job applications",
          emails: emails.map { |email|
            email["tags"] = tags_by_id[email["id"]]&.fetch("tags", []) || []
            email
          }
        }.to_json
        # steep:ignore:end

        Orchestration::Agents::EmailsFilter.create.with_model(@model).ask(input).content
      end

      def map_emails(emails:)
        input = { emails: emails }.to_json
        content = Orchestration::Agents::EmailsMapper.create
          .with_model(@model)
          .with_schema(ApplicationMailsSchema)
          .ask(input)
          .content

        return content.transform_keys(&:to_s) if content.is_a?(Hash)

        {}
      end

      def store_mapped_emails(emails:)
        input = { table: "application_mails", label: "applications", emails: emails }.to_json
        content = Orchestration::Agents::RecordsStorer.create.with_model(@model).ask(input).content
        return content.transform_keys(&:to_s) if content.is_a?(Hash)

        {}
      end

      def normalize_stored_emails(emails: [])
        input = {
          records_to_normalize: emails,
          destination_table: "application_mails",
          columns_to_normalize: [ "company", "job_title" ]
        }.to_json

        Orchestration::Agents::RecordsNormalizer.create.with_model(@model).ask(input).content
      end

      def reconcile_emails_to_interviews(emails: [])
        return {} if emails.empty?

        input = {
          emailsto_reconcile: emails,
          destination_table: "interviews",
          matching_columns: [ "company", "job_title" ],
          matching_logic: "match on both company + job_title, there could be some duplicates and that's ok, just do your best to match and reconcile based on these columns",
          statuses: [ "pending_reply", "having_interviews", "rejected", "offer_received" ],
          initial_status: "pending_reply"
        }.to_json
        Orchestration::Agents::RecordsReconciler.create.with_model(@model).ask(input).content
      end
    end
  end
end
