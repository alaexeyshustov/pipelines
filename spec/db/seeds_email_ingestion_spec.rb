require "rails_helper"

RSpec.describe "Seeds: Email Ingestion pipeline" do # rubocop:disable RSpec/DescribeClass
  let(:legacy_class) { "Orchestration::Executors::EmailsSync" }
  let(:pipelines) { Orchestration::Pipeline.where(name: "Email Ingestion") }

  # Seeding is per-record by design; the examples check what it left behind.
  def seed = Prosopite.pause { load Rails.root.join("db/seeds.rb") }

  # The legacy action is saved without validation: its executor class is gone after this change, and the validation
  # insists on an existing constant.
  def legacy_action(name: "Sync Inbox Emails")
    Orchestration::Action.find_by(name:, agent_class: legacy_class) ||
      Orchestration::Action.new(name:, kind: "service", agent_class: legacy_class).tap { |action| action.save!(validate: false) }
  end

  def legacy_pipeline(name:, action: legacy_action, runs: 0)
    create(:orchestration_pipeline, name:, cron_expression: "*/30 * * * *").tap do |pipeline|
      step = create(:orchestration_step, pipeline:, position: 1, name: action.name)
      step_action = create(:orchestration_step_action, step:, action:, output_key: "sync_inbox_emails")
      runs.times do
        run = create(:orchestration_pipeline_run, pipeline:, status: "completed")
        create(:orchestration_action_run, pipeline_run: run, step_action:, status: "completed")
      end
    end
  end

  before { allow(Rails.logger).to receive(:warn) }

  context "with a fresh database" do
    it "imports the six-step pipeline, enabled and without a cron" do
      seed

      pipeline = pipelines.sole
      expect(pipeline).to have_attributes(enabled: true, cron_expression: nil)
      expect(pipeline.steps.count).to eq(6)
    end

    it "is a no-op the second time" do
      seed
      first = pipelines.sole

      expect { seed }.not_to(change { [ Orchestration::Pipeline.count, Orchestration::Step.count, Orchestration::Action.count ] })

      expect(pipelines.sole.id).to eq(first.id)
    end

    it "keeps a pipeline the user disabled disabled when the seeds run again" do
      seed
      pipelines.sole.update!(enabled: false)

      seed

      expect(pipelines.sole).not_to be_enabled
    end
  end

  context "with the legacy pipeline and its runs" do
    let!(:legacy) { legacy_pipeline(name: "Email Ingestion", runs: 2) }

    it "removes it with its runs and action runs, and imports the new one in its place", :aggregate_failures do
      seed

      expect(Orchestration::Pipeline.exists?(legacy.id)).to be(false)
      expect(Orchestration::PipelineRun.where(pipeline_id: legacy.id)).to be_empty
      expect(Orchestration::ActionRun.count).to eq(0)
      expect(pipelines.sole.steps.count).to eq(6)
      expect(pipelines.sole).to be_enabled
    end

    it "removes the Sync Inbox Emails action when nothing else uses it" do
      seed

      expect(Orchestration::Action.where(agent_class: legacy_class)).to be_empty
    end

    it "keeps an unused EmailsSync action under another name" do
      other_action = legacy_action(name: "My Mail Action")

      seed

      expect(Orchestration::Action.exists?(other_action.id)).to be(true)
      expect(Orchestration::Action.where(name: "Sync Inbox Emails")).to be_empty
    end

    it "logs no warning when no other pipeline uses the legacy executor" do
      seed

      expect(Rails.logger).not_to have_received(:warn).with(/#{legacy_class}|EmailsSync/)
    end
  end

  context "with another pipeline that still has an EmailsSync step" do
    let!(:legacy) { legacy_pipeline(name: "Email Ingestion", runs: 1) }
    let!(:other) { legacy_pipeline(name: "My Own Mail Sync", action: legacy_action) }

    it "keeps that pipeline and the action it uses, and still replaces the legacy Email Ingestion", :aggregate_failures do
      seed

      expect(Orchestration::Pipeline.exists?(other.id)).to be(true)
      expect(other.steps.sole.step_actions.sole.action).to have_attributes(agent_class: legacy_class)
      expect(Orchestration::Pipeline.exists?(legacy.id)).to be(false)
      expect(pipelines.sole.steps.count).to eq(6)
    end

    it "logs a warning naming that pipeline" do
      seed

      expect(Rails.logger).to have_received(:warn).with(a_string_including("My Own Mail Sync"))
    end
  end

  context "when an Email Ingestion pipeline without an EmailsSync step already exists" do
    let!(:existing) { create(:orchestration_pipeline, name: "Email Ingestion", enabled: false) }

    it "is left alone and no second one is imported" do
      seed

      expect(pipelines.sole).to eq(existing)
      expect(existing.reload).not_to be_enabled
      expect(existing.steps.count).to eq(0)
    end
  end
end
