require "date"

module Pipeline
  class ApplicationsWorkflow
    def initialize(model:, logger:, date: Time.zone.today)
      @model  = model
      @logger = logger
      @date   = date.is_a?(Date) ? date : Date.parse(date.to_s)
      @agent_steps = AgentSteps.new(model: @model)
    end

    def run
      @logger.info "Running ApplicationsWorkflow with model: #{@model}"

      all_emails = EmailProviderFetcher.new(date: @date).call
      return { status: "no_emails_fetched" }  if all_emails.empty?

      filtered_emails = filter_emails(all_emails)
      return { status: "no_filtered_emails" } if filtered_emails.empty?

      saved_emails = map_and_store(filtered_emails)
      return { status: "no_mapped_emails" }   if saved_emails.nil?

      { status: "test_complete", model_used: @model, result: finalize(saved_emails) }
    end

    def step8_upload_csv_gist(gist_id:)
      @logger.info "Uploading gist #{gist_id}"
      result = Interviews::GistExportService.new(ids: nil, gist_id: gist_id).call
      { "ok" => result.ok, "message" => result.message }
    end

    private

    def filter_emails(all_emails)
      tags         = results_from(@agent_steps.classify_email(emails: all_emails))
      filtered_ids = results_from(@agent_steps.filter_emails(emails: all_emails, tags: tags)).filter_map do |res|
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
      mapped_value = @agent_steps.map_emails(emails: filtered_emails)["emails"]
      mapped_emails = mapped_value.is_a?(Array) ? mapped_value.filter_map { |email| email if email.is_a?(Hash) } : [] # : Array[json_object]
      return nil if mapped_emails.empty?

      ids_value    = @agent_steps.store_mapped_emails(emails: mapped_emails)["ids"]
      email_ids    = ids_value.is_a?(Array) ? ids_value : [] # : Array[json_object_value]
      saved_emails = ApplicationMail.groupped.where(id: email_ids).map(&:attributes)
      @agent_steps.normalize_stored_emails(emails: saved_emails)
      saved_emails
    end

    def finalize(saved_emails)
      result  = @agent_steps.reconcile_emails_to_interviews(emails: saved_emails)
      gist_id = ENV.fetch("GIST_ID", nil)
      gist_id ? step8_upload_csv_gist(gist_id: gist_id) : result
    end
  end
end
