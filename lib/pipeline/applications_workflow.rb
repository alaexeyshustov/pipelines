require "date"
require "json"
require "async"
require "async/semaphore"

module Pipeline
  class ApplicationsWorkflow
    def initialize(model:, logger:, date: Date.today)
      @model  = model
      @logger = logger
      @date   = date.is_a?(String) ? Date.parse(date) : date
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
      return JSON.parse(File.read(tmp_file)) if File.exist?(tmp_file)

      emails = fetch_from_providers
      File.write(tmp_file, emails.to_json)
      emails
    end

    def step2_classify_email(emails:)
      input = { emails: emails.map { |email| email.slice("id", "subject") } }.to_json

      Emails::ClassifyAgent.create.with_model(@model).ask(input).content
    end

    def step3_filter_emails(emails:, tags:)
      tags_by_id = tags.index_by { |tag| tag["id"] }
      input = {
        topic: "job applications",
        emails: emails.map { |email|
          email[:tags] = tags_by_id[email["id"]]&.fetch("tags", []) || []
          email
        }
      }.to_json

      Emails::FilterAgent.create.with_model(@model).ask(input).content
    end

    def step4_map_emails(emails:)
      input = {
        emails: emails
      }.to_json

      Emails::MappingAgent.create
        .with_model(@model)
        .with_schema(ApplicationMailsSchema)
        .ask(input)
        .content
    end

    def step5_store_mapped_emails(emails:)
      input = {
        table: "application_mails",
        label: "applications",
        emails: emails
      }.to_json

      Records::StoreAgent.create.with_model(@model).ask(input).content
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
      Interviews::GistExportService.new(ids: nil, gist_id: gist_id).call
    end

    private

    def filter_emails(all_emails)
      tags         = results_from(step2_classify_email(emails: all_emails))
      filtered_ids = results_from(step3_filter_emails(emails: all_emails, tags: tags)).map { |res| res["id"] }
      all_emails.select { |email| filtered_ids.include?(email["id"]) }
    end

    def results_from(response)
      @logger.debug "Extracting results from response"
      response.is_a?(Hash) ? response["results"] || [] : []
    end

    def map_and_store(filtered_emails)
      mapped_emails = step4_map_emails(emails: filtered_emails)["emails"] || []
      return nil if mapped_emails.empty?

      email_ids    = step5_store_mapped_emails(emails: mapped_emails)["ids"] || []
      saved_emails = ApplicationMail.where(id: email_ids).groupped.map(&:attributes)
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
            result.is_a?(Array) ? result : (result["results"] || result[:results] || [])
          end
        end
        tasks.flat_map(&:wait)
      end
    end
  end
end
