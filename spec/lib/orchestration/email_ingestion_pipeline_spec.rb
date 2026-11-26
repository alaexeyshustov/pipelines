require "rails_helper"

# End to end: the checked-in Email Ingestion pipeline through PipelineRunner (GH #248). Only the boundaries are
# replaced: the Gmail and Yahoo adapters (fake adapters with BaseAdapter's reader signatures, behind Emails), Mistral OCR, the decisions endpoint of
# RubyLLM::Judge and the Ollama embeddings endpoint (WebMock).
# Per-record steps are the subject here, so the N+1 gate is off; the executors' loops are covered by their own
# specs (only Document::IngestEmailAttachments#document_id is allowlisted in spec/support/prosopite.rb).
RSpec.describe "Email Ingestion pipeline", prosopite: false do # rubocop:disable RSpec/DescribeClass
  include ActiveSupport::Testing::TimeHelpers
  include EmailAdapterHelpers
  include EmbeddingHelpers

  let(:json) { { "Content-Type" => "application/json" } }
  let(:ocr_url) { "https://api.mistral.ai/v1/ocr" }
  let(:decisions_url) { "https://api.openai.com/v1/decisions" }
  let(:pipeline_file) { Rails.root.join("config/pipelines/email_ingestion.json") }
  let(:pipeline) { Orchestration::PipelineImporter.call(JSON.parse(File.read(pipeline_file))).pipelines.sole }
  let(:gmail) { stub_gmail_adapter(inbox_message_ids_since: [], inbox_message_ids_after: []) }
  let(:yahoo) { stub_yahoo_adapter(inbox_uids_after: [], inbox_uids_since: []) }
  let(:cv) { { id: "att1", filename: "cv.pdf", mime_type: "application/pdf", size: 10 } }

  before do
    travel_to Time.zone.local(2026, 4, 1, 12)
    create(:tag, name: "job_application")
    allow(Rails.logger).to receive(:error)
    stub_ocr
    stub_decisions
    stub_embeddings
  end

  after { Emails.configure }

  # Distinct text per attachment, so the Documents get distinct vectors.
  def stub_ocr
    stub_request(:post, ocr_url).to_return do |request|
      { status: 200, headers: json,
        body: { model: "mistral-ocr-latest", pages: [ { "index" => 0, "markdown" => "Interview notes #{Zlib.crc32(request.body)}" } ] }.to_json }
    end
  end

  # The judge tags what mentions an interview and nothing else.
  def stub_decisions
    stub_request(:post, decisions_url).to_return do |request|
      body = JSON.parse(request.body)
      probability = body.fetch("input").match?(/interview/i) ? 0.9 : 0.1
      answers = body.fetch("questions").map { |question| { "name" => question["name"], "probability" => probability } }
      { status: 200, headers: json, body: { model: "gpt-6-luna", answers:, usage: { input_tokens: 10, output_tokens: 2 } }.to_json }
    end
  end

  def stub_embeddings
    stub_request(:post, EmbeddingHelpers::OLLAMA_EMBEDDINGS_URL).to_return do |request|
      inputs = JSON.parse(request.body).fetch("input")
      { status: 200, headers: json, body: { data: inputs.map { |text| { embedding: unit_vector(Zlib.crc32(text) % 1000) } } }.to_json }
    end
  end

  # A Gmail message with optional attachments (id => bytes).
  def gmail_mail(id, subject:, attachments: {})
    allow(gmail).to receive(:fetch_message).with(id).and_return(adapter_message(id, subject:, date: Time.utc(2026, 3, 30, 8)))
    stub_gmail_attachments(id, attachments)
  end

  def stub_gmail_attachments(id, attachments)
    allow(gmail).to receive(:attachments).with(id).and_return(attachments.keys.map { |att_id| cv.merge(id: att_id) })
    attachments.each { |att_id, bytes| stub_gmail_attachment(id, att_id, bytes) }
  end

  def stub_gmail_attachment(id, att_id, bytes)
    allow(gmail).to receive(:attachment).with(id, att_id).and_return(bytes)
  end

  def usable_gmail_cursor
    create(:email_sync_cursor, provider: "gmail", account: EmailAdapterHelpers::GMAIL_ACCOUNT, history_id: "100",
                               last_synced_at: Time.zone.local(2026, 3, 30, 9))
  end

  def gmail_cursor = Email::SyncCursor.find_by(provider: "gmail", account: EmailAdapterHelpers::GMAIL_ACCOUNT)

  def run_pipeline(initial_input)
    run = create(:orchestration_pipeline_run, pipeline:, status: "pending", initial_input:)
    Orchestration::PipelineRunner.new(run).run
    run.reload
  end

  # [list, classify emails, embed emails, ingest attachments, classify documents, embed documents]
  def action_runs(run)
    Orchestration::ActionRun.where(pipeline_run: run).includes(step_action: :step).sort_by { |ar| ar.step_action.step.position }
  end

  def outputs(run) = action_runs(run).map(&:output)

  def email(message_id) = Email.find_by!(provider_message_id: message_id)

  describe "with blank dates and a usable cursor" do
    let(:input) { { "providers" => [ "gmail" ], "date_from" => "", "date_to" => "" } }

    before do
      usable_gmail_cursor
      allow(gmail).to receive(:inbox_message_ids_since).with("100").and_return(%w[g1 g2])
      gmail_mail("g1", subject: "Interview with Acme", attachments: { "att1" => "%PDF-cv" })
      gmail_mail("g2", subject: "Weekly newsletter")
    end

    it "reads incrementally and advances the cursor", :aggregate_failures do
      run = run_pipeline(input)

      expect(run.status).to eq("completed")
      expect(gmail).to have_received(:inbox_message_ids_since).with("100")
      expect(gmail).not_to have_received(:inbox_message_ids_after)
      expect(gmail_cursor).to have_attributes(history_id: "500", last_synced_at: Time.current)
    end

    it "treats date keys that are missing from the initial input as blank" do
      run = run_pipeline({ "providers" => [ "gmail" ] })

      expect(run.status).to eq("completed")
      expect(outputs(run).first.dig("providers", "gmail", "mode")).to eq("incremental")
    end

    it "stores the emails, tags the one about an interview and leaves the other untagged" do
      run_pipeline(input)

      expect(Email.count).to eq(2)
      expect(email("g1")).to be_tagged
      expect(email("g2")).to be_untagged
    end

    it "embeds only the tagged email and ingests attachments only for it", :aggregate_failures do
      run_pipeline(input)

      expect(email("g1").embeddings.count).to eq(1)
      expect(email("g2").embeddings.count).to eq(0)
      expect(gmail).to have_received(:attachments).with("g1")
      expect(gmail).not_to have_received(:attachments).with("g2")
    end

    it "classifies and embeds the attachment's document" do
      run_pipeline(input)

      document = Document.sole
      expect(document).to have_attributes(title: "cv.pdf", email_id: email("g1").id, classification_status: "tagged")
      expect(document.embeddings.count).to eq(1)
    end

    it "completes every step and reports the listing on the first ActionRun", :aggregate_failures do
      run = run_pipeline(input)
      list, = outputs(run)

      expect(action_runs(run).map(&:status)).to all(eq("completed"))
      expect(list).to include("email_ids" => contain_exactly(email("g1").id, email("g2").id))
      expect(list["providers"]["gmail"]).to include("mode" => "incremental", "fetched" => 2, "stored" => 2)
    end

    it "stores each later step's output on its ActionRun", :aggregate_failures do
      _list, classify, embed, ingest, classify_documents, embed_documents = outputs(run_pipeline(input))
      g1 = email("g1").id
      g2 = email("g2").id
      document = Document.sole.id

      expect(classify).to eq("tagged" => [ g1 ], "untagged" => [ g2 ], "failed" => [])
      expect(embed).to eq("embedded" => [ g1 ], "skipped" => [ g2 ], "failed" => [])
      expect(ingest).to eq("document_ids" => [ document ], "skipped" => [ g2 ], "failed" => [])
      expect(classify_documents).to eq("tagged" => [ document ], "untagged" => [], "failed" => [])
      expect(embed_documents).to include("embedded" => [ document ], "failed" => [])
    end
  end

  describe "with a historical range" do
    let(:input) { { "providers" => [ "gmail" ], "date_from" => "2026-03-01", "date_to" => "2026-03-10" } }

    before do
      allow(gmail).to receive(:inbox_message_ids_after).and_return(%w[h1])
      gmail_mail("h1", subject: "Interview long ago")
    end

    it "lists only that range, with an upper bound at the start of the day after date_to", :aggregate_failures do
      run = run_pipeline(input)

      expect(gmail).to have_received(:inbox_message_ids_after).with(Time.zone.local(2026, 3, 1), before: Time.zone.local(2026, 3, 11))
      expect(gmail).not_to have_received(:inbox_message_ids_since)
      expect(outputs(run).first.dig("providers", "gmail", "mode")).to eq("historical")
      expect(email("h1")).to be_tagged
    end

    it "leaves the cursor untouched" do
      usable_gmail_cursor
      before_state = gmail_cursor.attributes

      run_pipeline(input)

      expect(gmail_cursor.reload.attributes).to eq(before_state)
    end

    it "creates no cursor when there was none" do
      run_pipeline(input)

      expect(Email::SyncCursor.count).to eq(0)
    end
  end

  describe "with some providers selected" do
    it "reads only those", :aggregate_failures do
      yahoo
      allow(gmail).to receive(:inbox_message_ids_after).and_return([])

      run = run_pipeline({ "providers" => [ "gmail" ] })

      expect(run.status).to eq("completed")
      expect(outputs(run).first["providers"].keys).to eq([ "gmail" ])
      expect(yahoo).not_to have_received(:inbox_status)
      expect(yahoo).not_to have_received(:inbox_uids_since)
    end
  end

  describe "with manual tagging" do
    it "embeds a manually tagged email and ingests its attachments, though the classifier never saw it", :aggregate_failures do
      manual = create(:email, provider: "gmail", provider_message_id: "man1", subject: "Lunch plans")
      finance = create(:tag, name: "finance")
      Tags::ManualTaggingForm.new(taggable: manual, tag_id: finance.id, subtag_id: nil).save
      gmail_mail("man1", subject: "Lunch plans", attachments: { "att1" => "%PDF-lunch" })

      run = run_pipeline({ "providers" => [ "gmail" ] })

      expect(run.status).to eq("completed")
      expect(manual.reload).to be_tagged
      expect(manual.embeddings.count).to eq(1)
      expect(Document.sole.email_id).to eq(manual.id)
    end
  end

  describe "with the same attachment on two emails" do
    before do
      allow(gmail).to receive(:inbox_message_ids_after).and_return(%w[d1 d2])
      gmail_mail("d1", subject: "Interview round one", attachments: { "att1" => "%PDF-same" })
      gmail_mail("d2", subject: "Interview round two", attachments: { "att2" => "%PDF-same" })
    end

    it "OCRs it once, keeps one Document, and passes its id on once", :aggregate_failures do
      run = run_pipeline({ "providers" => [ "gmail" ] })

      expect(a_request(:post, ocr_url)).to have_been_made.once
      document = Document.sole
      expect(document).to be_tagged
      expect(document.embeddings.count).to eq(1)
      expect(outputs(run)[3]["document_ids"]).to eq([ document.id ])
    end
  end

  describe "when one provider fails" do
    before do
      allow(gmail).to receive(:inbox_message_ids_after).and_raise(Google::Apis::ServerError.new("gmail down"))
      allow(yahoo).to receive(:inbox_uids_since).and_return([ 3 ])
      allow(yahoo).to receive(:fetch_message).with("777:3")
                                              .and_return(adapter_message("777:3", provider: "yahoo", subject: "Interview at Initech"))
    end

    it "still processes the other, reports the error, and skips attachments for the Yahoo email", :aggregate_failures do
      run = run_pipeline({ "providers" => %w[gmail yahoo] })

      expect(run.status).to eq("completed")
      list, _classify, embed, ingest = outputs(run)
      expect(list["providers"]["gmail"]).to include("error" => a_string_including("gmail down"))
      expect(list["providers"]["yahoo"]).to include("stored" => 1)
      yahoo_email = email("777:3")
      expect(yahoo_email).to be_tagged
      expect(embed["embedded"]).to eq([ yahoo_email.id ])
      expect(ingest).to include("document_ids" => [], "skipped" => [ yahoo_email.id ])
    end
  end

  describe "when every provider fails or is skipped" do
    it "fails the first step with the per-provider JSON in the error, and runs nothing after it", :aggregate_failures do
      allow(gmail).to receive(:inbox_message_ids_after).and_raise(Google::Apis::ServerError.new("gmail down"))
      allow(yahoo).to receive(:inbox_uids_since).and_raise(RuntimeError, "imap down")

      run = run_pipeline({ "providers" => %w[gmail yahoo] })

      expect(run.status).to eq("failed")
      expect(action_runs(run).sole.status).to eq("failed")
      providers = JSON.parse(run.error[/Output: (.*)\z/m, 1]).fetch("providers")
      expect(providers["gmail"]["error"]).to include("gmail down")
      expect(providers["yahoo"]["error"]).to include("imap down")
    end

    it "fails the same way when every provider lacks credentials" do
      stub_unconfigured_adapter("gmail")
      stub_unconfigured_adapter("yahoo")

      run = run_pipeline({ "providers" => %w[gmail yahoo] })

      expect(run.status).to eq("failed")
      providers = JSON.parse(run.error[/Output: (.*)\z/m, 1]).fetch("providers")
      expect(providers.values).to all(include("mode" => "skipped"))
      expect(action_runs(run).size).to eq(1)
    end
  end

  describe "a re-run with nothing new from the provider" do
    let!(:pending_email) { create(:email, provider: "gmail", provider_message_id: "p1", subject: "Interview pending") }
    let!(:failed_email) { create(:email, provider: "gmail", provider_message_id: "f1", subject: "Interview failed", classification_status: "failed") }
    let!(:unembedded) { create(:email, provider: "gmail", provider_message_id: "u1", subject: "Interview tagged", classification_status: "tagged") }
    let!(:untagged_email) { create(:email, provider: "gmail", provider_message_id: "n1", subject: "Interview analysed", classification_status: "untagged") }
    let!(:pending_document) { create(:document, email: unembedded, text: "Interview pending doc", classification_status: "pending") }
    let!(:failed_document) { create(:document, email: unembedded, text: "Interview failed doc", classification_status: "failed") }

    before do
      usable_gmail_cursor
      allow(gmail).to receive_messages(inbox_message_ids_since: [], attachments: [])
    end

    it "classifies pending and failed emails" do
      run_pipeline({ "providers" => [ "gmail" ] })

      expect(pending_email.reload).to be_tagged
      expect(failed_email.reload).to be_tagged
    end

    it "embeds tagged emails that have no embedding, and leaves the untagged one out", :aggregate_failures do
      run_pipeline({ "providers" => [ "gmail" ] })

      expect(unembedded.embeddings.count).to eq(1)
      expect(pending_email.embeddings.count).to eq(1)
      expect(untagged_email.reload.embeddings.count).to eq(0)
      expect(untagged_email).to be_untagged
    end

    it "classifies and embeds the pending and failed documents of the processed emails" do
      run_pipeline({ "providers" => [ "gmail" ] })

      expect([ pending_document, failed_document ].map { |document| document.reload.classification_status }).to eq(%w[tagged tagged])
      expect([ pending_document, failed_document ].map { |document| document.embeddings.count }).to eq([ 1, 1 ])
    end

    it "classifies and embeds the leftover documents of an email that is already tagged and embedded", :aggregate_failures do
      done = create(:email, provider: "gmail", provider_message_id: "d1", subject: "Interview done", classification_status: "tagged")
      embed_as(done, unit_vector(1))
      leftover = create(:document, email: done, text: "Interview leftover doc", classification_status: "failed")

      run_pipeline({ "providers" => [ "gmail" ] })

      expect(leftover.reload).to be_tagged
      expect(leftover.embeddings.count).to eq(1)
    end
  end
end
