require "date"
require "json"
require "async"
require "async/semaphore"

module Pipeline
  class ApplicationsWorkflow
    def initialize(model:, logger:, date: Date.today)
      @model  = model
      @logger = logger
      @date   = date.is_a?(Date) ? date : Date.parse(date.to_s)
    end

    def run
      @logger.info "Running ApplicationsWorkflow with model: #{@model}"

      all_emails = step1_fetch_emails
      return { status: "no_emails_fetched" }  if all_emails.empty?

      filtered_emails = filter_emails(all_emails)
      return { status: "no_filtered_emails" } if filtered_emails.empty?

      saved_emails = map_and_store(filtered_emails)
      return { status: "no_mapped_emails" }   if saved_emails.nil?

      { status: "test_complete", model_used: @model, result: finalize(saved_emails) }
    end

    def step1_fetch_emails
      tmp_file = Rails.root.join("tmp", "emails_#{@date - 1}_#{@date}.json")
      if File.exist?(tmp_file)
        cached = JSON.parse(tmp_file.read)
        return cached.filter_map { |email| email if email.is_a?(Hash) } if cached.is_a?(Array)
      end

      emails = fetch_from_providers
      tmp_file.write(emails.to_json)
      emails
    end

    def step2_classify_email(emails:)
      input = { emails: emails.map { |email| email.slice("id", "subject") } }.to_json

      Emails::ClassifyAgent.create.with_model(@model).ask(input).content
    end

    def step3_filter_emails(emails:, tags:)
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

      Emails::FilterAgent.create.with_model(@model).ask(input).content
    end

    def step4_map_emails(emails:)
      input = { emails: emails }.to_json
      content = Emails::MappingAgent.create
        .with_model(@model)
        .with_schema(ApplicationMailsSchema)
        .ask(input)
        .content

      return content.transform_keys(&:to_s) if content.is_a?(Hash)

      {}
    end

    def step5_store_mapped_emails(emails:)
      input = { table: "application_mails", label: "applications", emails: emails }.to_json
      content = Records::StoreAgent.create.with_model(@model).ask(input).content
      return content.transform_keys(&:to_s) if content.is_a?(Hash)

      {}
    end

    def step6_normalize_stored_emails(emails: [])
      input = {
        records_to_normalize: emails,
        destination_table: "application_mails",
        columns_to_normalize: [ "company", "job_title" ]
      }.to_json

      Records::NormalizeAgent.create.with_model(@model).ask(input).content
    end

    def step7_reconcile_emails_to_interviews(emails: [])
      return {} if emails.empty?

      input = {
        emailsto_reconcile: emails,
        destination_table: "interviews",
        matching_columns: [ "company", "job_title" ],
        matching_logic: "match on both company + job_title, there could be some duplicates and that's ok, just do your best to match and reconcile based on these columns",
        statuses: [ "pending_reply", "having_interviews", "rejected", "offer_received" ],
        initial_status: "pending_reply"
      }.to_json
      Records::ReconcileAgent.create.with_model(@model).ask(input).content
    end

    def step8_upload_csv_gist(gist_id:)
      @logger.info "Uploading gist #{gist_id}"
      result = Interviews::GistExportService.new(ids: nil, gist_id: gist_id).call
      { "ok" => result.ok, "message" => result.message }
    end

    private

    def filter_emails(all_emails)
      tags         = results_from(step2_classify_email(emails: all_emails))
      filtered_ids = results_from(step3_filter_emails(emails: all_emails, tags: tags)).filter_map do |res|
        id = res["id"]
        id if id.is_a?(String)
      end
      all_emails.select do |email|
        id = email["id"]
        next false unless id.is_a?(String)

        filtered_ids.include?(id.to_s)
      end
    end

    def results_from(response)
      @logger.debug "Extracting results from response"
      return [] unless response.is_a?(Hash)

      results = response["results"]
      results.is_a?(Array) ? results.filter_map { |result| result if result.is_a?(Hash) } : []
    end

    def map_and_store(filtered_emails)
      mapped_value = step4_map_emails(emails: filtered_emails)["emails"]
      mapped_emails = mapped_value.is_a?(Array) ? mapped_value.filter_map { |email| email if email.is_a?(Hash) } : [] # : Array[json_object]
      return nil if mapped_emails.empty?

      ids_value    = step5_store_mapped_emails(emails: mapped_emails)["ids"]
      email_ids    = ids_value.is_a?(Array) ? ids_value : [] # : Array[json_object_value]
      saved_emails = ApplicationMail.groupped.where(id: email_ids).map(&:attributes)
      step6_normalize_stored_emails(emails: saved_emails)
      saved_emails
    end

    def finalize(saved_emails)
      result  = step7_reconcile_emails_to_interviews(emails: saved_emails)
      gist_id = ENV.fetch("GIST_ID", nil)
      gist_id ? step8_upload_csv_gist(gist_id: gist_id) : result
    end

    def fetch_from_providers
      Sync do
        semaphore = Async::Semaphore.new(5)
        tasks = [ "gmail", "yahoo" ].map do |provider|
          semaphore.async do
            result = step1(provider: provider, after: @date - 1, before: @date)
            if result.is_a?(Array)
              result.filter_map { |email| email if email.is_a?(Hash) }
            elsif result.is_a?(Hash)
              results = result["results"]
              results.is_a?(Array) ? results.filter_map { |email| email if email.is_a?(Hash) } : []
            else
              []
            end
          end
        end
        tasks.flat_map(&:wait)
      end
    end
  end
end
