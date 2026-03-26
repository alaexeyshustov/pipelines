module Pipeline
  class TestWorkflow
    def initialize(model:, logger:, date: Date.today)
      @model  = model
      @logger = logger
      @date   = date.is_a?(String) ? Date.parse(date) : date
    end

    def run
      @logger.info "Running TestWorkflow with model: #{@model}"
      # Simulate some processing and return a test result

      all_emails= fetach_emails
      return { status: "no_emails_fetched" } if all_emails.empty?

      results = step2(emails: all_emails)
      tags = results["results"] || []
      puts "Classified #{tags.size} emails: #{tags}"

      results = step3(emails: all_emails, tags: tags)
      filtered_ids = (results["results"] || []).map { |email| email["id"] }
      puts "Filtered #{filtered_ids.size} ids: #{filtered_ids}"

      return { status: "no_filtered_emails" } if filtered_ids.empty?

      filtered_emails = all_emails.select { |email| filtered_ids.include?(email["id"]) }
      puts "Filtered #{filtered_emails.size} emails: #{filtered_emails}"

      results = step4(emails: filtered_emails)
      mapped_emails = results["results"] || []
      puts "Mapped emails to records: #{mapped_emails}"

      results = step5(emails: mapped_emails)
      email_ids = results["results"] || []
      puts "Stored IDs: #{email_ids}"

      emails = ApplicationMail.groupped.map(&:attributes)

      results = step6(emails: emails)
      normalized_records = results["results"] || []
      puts "Normalized records: #{normalized_records}"

      result = step7(emails: emails)

      { status: "test_complete", model_used: @model, result: result }
    end

    def step1(provider:, after:, before:)
      Emails::RetrievalService.new(provider: provider, after_date: after, before_date: before).call
    end

    def step2(emails:)
      input = { emails: emails.map { |email| { id: email["id"], subject: email["subject"] } } }.to_json

      Emails::ClassifyAgent.create.with_model(@model).ask(input).content
    end

    def step3(emails:, tags:)
      input = {
        topic: "job applications",
        emails: emails.map do |email|
          email[:tags] = tags.find { |t| t["id"] == email["id"] }&.fetch("tags", []) || []
          email
        end
      }.to_json

      Emails::FilterAgent.create.with_model(@model).ask(input).content
    end

    def step4(emails:)
      input = {
        emails: emails
      }.to_json

      Emails::MappingAgent.create
        .with_model(@model)
        .with_schema(ApplicationMailsSchema)
        .ask(input)
        .content
    end

    def step5(emails:)
      input = {
        table: "application_mails",
        label: "applications",
        emails: emails
      }.to_json

      Records::StoreAgent.create.with_model(@model).ask(input).content
    end

    def step6(emails: [])
      input = {
        records_to_normalize: emails,
        destination_table: "application_mails",
        columns_to_normalize: [ "company", "job_title" ]
      }.to_json

      Records::NormalizeAgent.create.with_model(@model).ask(input).content
    end

    def step7(emails: [])
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

    def fetach_emails
      tmp_file = Rails.root.join("tmp", "emails_#{start_date}_#{end_date}.json")
      if File.exist?(tmp_file)
        JSON.parse(File.read(tmp_file))
      else
        emails = Sync do
          semaphore = Async::Semaphore.new(5)
          tasks = [ "gmail", "yahoo" ].map do |provider|
            semaphore.async do
              result = step1(provider: provider, after: start_date, before: end_date)
              result = result.is_a?(Array) ? result : (result["results"] || result[:results] || [])
              result
            end
          end
          tasks.flat_map(&:wait)
        end
        File.write(tmp_file, emails.to_json)
        emails
      end
    end

    def start_date
      @date - 1
    end

    def end_date
      @date
    end
  end
end
