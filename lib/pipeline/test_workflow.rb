module Pipeline
  class TestWorkflow
    def initialize(model:, logger:)
      @model  = model
      @logger = logger
    end

    def run
      @logger.info "Running TestWorkflow with model: #{@model}"
      # Simulate some processing and return a test result
      result1 = step1(provider: "gmail", after: "2026-03-17", before: "2026-03-19")
      result2 = step2(results: result1)
      result3 = step3(results: result2)

      { status: "test_complete", model_used: @model, step3_result: result3 }
    end

    def step1(provider:, after:, before:)
      input = {
        provider: provider,
        after_date: after,
        before_date: before
      }.to_json

      EmailFetchAgent.create.ask(input).content
    end

    def step2(results:)
      emails = results.is_a?(Array) ? results : (results["results"] || results[:results] || [])
      input = { topic: "job applications", emails: emails }.to_json

      EmailFilterAgent.create.ask(input).content
    end

    def step3(results:)
      emails = results.is_a?(Array) ? results : (results["results"] || results[:results] || [])
      input = {
        table: "application_mails",
        label: "applications",
        emails: emails
      }.to_json

      LabelAndStoreAgent.create.ask(input).content
    end
  end
end
