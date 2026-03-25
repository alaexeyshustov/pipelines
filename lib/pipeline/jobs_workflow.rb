require "date"
require "json"
require "async"
require "async/semaphore"

module Pipeline
  # Sequential multi-agent workflow for job application email tracking.
  # No MCP — tools are plain RubyLLM::Tool instances injected directly into agents.
  class JobsWorkflow
    PROVIDERS = %w[gmail yahoo].freeze
    BATCH_SIZE = 15
    MAX_CONCURRENT_REQUESTS = 2
    LOOKBACK_MONTHS = ENV.fetch("LOOKBACK_MONTHS", "3").to_i
    MODELS_POOL = [ "", "gpt-4.1" ].freeze
    RATE_LIMIT_SWITCH_AFTER = 2
    RATE_LIMIT_BASE_DELAY   = 5

    def initialize(registry:, model: nil, logger: Pipeline::Logger.new)
      @registry = registry
      @model    = model
      @logger   = logger
      @prompts  = Prompts.new
      @tools    = build_tools
    end

    def run
      cutoff_date, existing_ids = step1_init_database
      dates = days_to_process(cutoff_date)

      total_fetched = 0
      total_job     = 0
      total_stored  = 0
      all_summaries = []

      dates.each_with_index do |date, idx|
        @logger.info "=== Day #{idx + 1}/#{dates.size}: #{date} ==="
        result = run_single_day(date, existing_ids)
        next if result[:emails].empty?

        existing_ids  |= result[:emails].map { |e| e["id"] }
        total_fetched += result[:emails].size
        next if result[:job_list].empty?

        total_job     += result[:job_list].size
        total_stored  += result[:added_rows].size
        all_summaries << result[:summary] if result[:summary]
      end

      return { status: "no_new_emails" } if total_fetched.zero?
      return { status: "no_job_emails" }  if total_job.zero?

      { status: "complete", new_emails: total_fetched, job_emails: total_job,
        rows_added: total_stored, reconcile_summaries: all_summaries }
    end

    private

    # ── Day runner ────────────────────────────────────────────────────────────

    def run_single_day(date, existing_ids)
      before_date = (Date.parse(date) + 1).iso8601
      day_emails  = step2_fetch_emails(date, before_date, existing_ids)

      if day_emails.empty?
        @logger.info "  No new emails, skipping."
        return { emails: [], job_list: [], added_rows: [], summary: nil }
      end

      day_job_list = step3_classify(day_emails)

      if day_job_list.empty?
        @logger.info "  No job emails, skipping."
        return { emails: day_emails, job_list: [], added_rows: [], summary: nil }
      end

      day_added_rows = step4_label_and_store(day_job_list)
      day_summary    = step5_reconcile(day_added_rows)

      { emails: day_emails, job_list: day_job_list, added_rows: day_added_rows, summary: day_summary }
    end

    # ── Steps ─────────────────────────────────────────────────────────────────

    def step1_init_database
      @logger.info "Step 1: Reading database state..."
      response     = run_agent(InitDatabaseAgent, @prompts.build_init_message)
      cutoff_date  = extract_date(response)
      existing_ids = extract_ids(response)
      @logger.debug "  cutoff=#{cutoff_date}, known_ids=#{existing_ids.size}"
      [ cutoff_date, existing_ids ]
    end

    def step2_fetch_emails(after_date, before_date, existing_ids)
      @logger.info "Step 2: Fetching emails from all providers..."

      all_emails = Sync do
        semaphore = Async::Semaphore.new(MAX_CONCURRENT_REQUESTS)
        tasks = PROVIDERS.map do |provider|
          semaphore.async do
            Emails::RetrievalService.new(provider: provider, after_date: after_date, before_date: before_date).call
          end
        end
        tasks.flat_map(&:wait)
      end

      @logger.debug "  fetched #{all_emails.size} total"
      new_emails = all_emails.reject { |e| existing_ids.include?(e["id"]) }
      @logger.debug "  #{new_emails.size} new after dedup"
      new_emails
    end

    def step3_classify(new_emails)
      @logger.info "Step 3: Classifying emails..."
      result   = run_agent(ClassifyAndFilterAgent, new_emails.to_json)
      job_list = parse_json_array(result)
      @logger.debug "  #{job_list.size} job emails found"
      job_list
    end

    def step4_label_and_store(job_list)
      @logger.info "Step 4: Labelling and storing..."

      added_rows = Sync do
        semaphore = Async::Semaphore.new(MAX_CONCURRENT_REQUESTS)
        tasks = job_list.each_slice(BATCH_SIZE).map do |batch|
          semaphore.async do
            result = run_agent(Records::StoreAgent, @prompts.build_label_store_message(batch))
            parse_json_array(result)
          end
        end
        tasks.flat_map(&:wait)
      end

      @logger.debug "  #{added_rows.size} rows added"
      added_rows
    end

    def step5_reconcile(added_rows)
      @logger.info "Step 5: Reconciling interviews..."
      summary = run_agent(Records::ReconcileAgent, @prompts.build_reconcile_message(added_rows))
      @logger.info "  reconciliation complete"
      summary
    end

    # ── Agent runner ──────────────────────────────────────────────────────────

    def run_agent(agent_class, message)
      models  = effective_models_pool
      m_idx   = 0
      retries = 0

      begin
        agent = agent_class.new
        agent.with_model(models[m_idx])
        agent.with_tools(*tools_for(agent_class))
        agent.ask(message).content
      rescue RubyLLM::RateLimitError => e
        retries += 1
        if retries > RATE_LIMIT_SWITCH_AFTER
          raise e if m_idx >= models.size - 1

          m_idx  += 1
          retries = 0
          @logger.warn "  Rate limit — switching to #{models[m_idx]}"
        else
          delay = RATE_LIMIT_BASE_DELAY * (2**(retries - 1))
          @logger.warn "  Rate limit (attempt #{retries}), retrying in #{delay}s..."
          sleep delay
        end
        retry
      end
    end

    def effective_models_pool
      return MODELS_POOL unless @model

      ([ @model ] + MODELS_POOL.reject { |m| m == @model }).freeze
    end

    def tools_for(agent_class)
      required = agent_class::TOOLS
      @tools.select { |t| required.include?(t.name) }
    end

    # ── Date helpers ──────────────────────────────────────────────────────────

    def days_to_process(cutoff_date)
      start_date = Date.parse(cutoff_date)
      today      = Date.today
      diff       = (today - start_date).to_i
      return [ cutoff_date ] if diff < 2

      (0...diff).map { |i| (start_date + i).iso8601 }
    end

    # ── Parsing helpers ────────────────────────────────────────────────────────

    def extract_date(text)
      data = safe_parse_json(text)
      date = data.is_a?(Hash) ? data["latest_date"] : nil
      (date.nil? || date == "no_date") ? default_beginning_date : date
    rescue StandardError
      default_beginning_date
    end

    def extract_ids(text)
      data = safe_parse_json(text)
      Array(data.is_a?(Hash) ? data["existing_ids"] : [])
    rescue StandardError
      []
    end

    def parse_json_array(text)
      return [] if text.nil? || text.strip.empty?

      json_str = text[/\[.*\]/m] || text
      result   = JSON.parse(json_str)
      return [] unless result.is_a?(Array)

      result.select { |e| e.is_a?(Hash) }
    rescue JSON::ParserError
      []
    end

    def safe_parse_json(text)
      return {} if text.nil? || text.strip.empty?

      json_str = text[/\{.*\}/m] || text
      JSON.parse(json_str)
    rescue JSON::ParserError
      {}
    end

    def default_beginning_date
      Date.today.prev_day.iso8601
    end
  end
end
