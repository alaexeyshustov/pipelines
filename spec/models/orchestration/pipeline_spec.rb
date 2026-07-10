require 'rails_helper'

RSpec.describe Orchestration::Pipeline do
  it { expect(described_class.table_name).to eq("orchestration_pipelines") }

  describe 'validations' do
    it 'is valid with required attributes' do
      pipeline = build(:orchestration_pipeline)
      expect(pipeline).to be_valid
    end

    it_behaves_like 'requires attribute', :name, :orchestration_pipeline

    it 'defaults enabled to true' do
      pipeline = described_class.new(name: 'My Pipeline')
      expect(pipeline.enabled).to be true
    end

    it 'is valid with a blank cron_expression' do
      pipeline = build(:orchestration_pipeline, cron_expression: '')
      expect(pipeline).to be_valid
    end

    it 'is valid with a valid cron_expression' do
      pipeline = build(:orchestration_pipeline, cron_expression: '0 * * * *')
      expect(pipeline).to be_valid
    end

    it 'is invalid with a malformed cron_expression' do
      pipeline = build(:orchestration_pipeline, cron_expression: 'not-a-cron')
      expect(pipeline).not_to be_valid
      expect(pipeline.errors[:cron_expression]).to be_present
    end
  end

  describe 'associations' do
    it 'destroys steps when pipeline is destroyed' do
      pipeline = create(:orchestration_pipeline)
      create(:orchestration_step, pipeline: pipeline)
      expect { pipeline.destroy }.to change(Orchestration::Step, :count).by(-1)
    end

    it 'destroys pipeline_runs when pipeline is destroyed' do
      pipeline = create(:orchestration_pipeline)
      create(:orchestration_pipeline_run, pipeline: pipeline)
      expect { pipeline.destroy }.to change(Orchestration::PipelineRun, :count).by(-1)
    end
  end

  describe 'model field' do
    it 'defaults model to nil' do
      pipeline = described_class.new(name: 'My Pipeline')
      expect(pipeline.model).to be_nil
    end

    it 'persists a model value' do
      pipeline = create(:orchestration_pipeline, model: 'mistral-small-latest')
      expect(pipeline.reload.model).to eq('mistral-small-latest')
    end
  end

  describe '#validate_steps' do
    it 'delegates to PipelineValidator#validate' do
      pipeline = build(:orchestration_pipeline)
      fake_results = []
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Orchestration::PipelineValidator).to receive(:validate).and_return(fake_results)
      # rubocop:enable RSpec/AnyInstance

      expect(pipeline.validate_steps).to eq(fake_results)
    end

    it 'returns an array of StepResult objects for a pipeline with steps' do
      pipeline = create(:orchestration_pipeline)

      result = pipeline.validate_steps

      expect(result).to be_an(Array)
    end
  end

  describe '#next_run_at' do
    it 'returns nil when cron_expression is nil' do
      pipeline = build(:orchestration_pipeline, cron_expression: nil)
      expect(pipeline.next_run_at).to be_nil
    end

    it 'returns nil when cron_expression is blank' do
      pipeline = build(:orchestration_pipeline, cron_expression: '')
      expect(pipeline.next_run_at).to be_nil
    end

    it 'returns the next scheduled time from the given reference time' do
      pipeline = build(:orchestration_pipeline, cron_expression: '0 * * * *')
      from = Time.utc(2026, 3, 30, 10, 0, 0)
      result = pipeline.next_run_at(from: from)
      expect(result).to eq(Time.utc(2026, 3, 30, 11, 0, 0))
    end

    it 'defaults from to Time.current when not provided' do
      pipeline = build(:orchestration_pipeline, cron_expression: '0 * * * *')
      result = pipeline.next_run_at
      expect(result).to be_a(Time)
      expect(result).to be > Time.current
    end
  end

  describe "#latest_run" do
    it "returns the most recently created run" do
      pipeline = create(:orchestration_pipeline)
      create(:orchestration_pipeline_run, pipeline: pipeline, created_at: 2.days.ago)
      newest = create(:orchestration_pipeline_run, pipeline: pipeline, created_at: 1.hour.ago)
      expect(pipeline.latest_run).to eq(newest)
    end

    it "returns nil when the pipeline has no runs" do
      pipeline = create(:orchestration_pipeline)
      expect(pipeline.latest_run).to be_nil
    end
  end

  describe "#run_in_progress?" do
    it "is true when a pending run exists" do
      pipeline = create(:orchestration_pipeline)
      create(:orchestration_pipeline_run, pipeline: pipeline, status: "pending")
      expect(pipeline.run_in_progress?).to be true
    end

    it "is true when a running run exists" do
      pipeline = create(:orchestration_pipeline)
      create(:orchestration_pipeline_run, pipeline: pipeline, status: "running")
      expect(pipeline.run_in_progress?).to be true
    end

    it "is false when only completed or failed runs exist" do
      pipeline = create(:orchestration_pipeline)
      create(:orchestration_pipeline_run, pipeline: pipeline, status: "completed")
      create(:orchestration_pipeline_run, pipeline: pipeline, status: "failed")
      expect(pipeline.run_in_progress?).to be false
    end

    it "is false when the pipeline has no runs" do
      pipeline = create(:orchestration_pipeline)
      expect(pipeline.run_in_progress?).to be false
    end
  end

  describe "#enabled_steps" do
    it "returns only enabled steps ordered by position" do
      pipeline = create(:orchestration_pipeline)
      step2 = create(:orchestration_step, pipeline: pipeline, position: 2, enabled: true)
      create(:orchestration_step, pipeline: pipeline, position: 3, enabled: false)
      step1 = create(:orchestration_step, pipeline: pipeline, position: 1, enabled: true)
      expect(pipeline.enabled_steps.to_a).to eq([ step1, step2 ])
    end
  end

  describe "#steps_with_actions" do
    it "returns the pipeline steps ordered by position" do
      pipeline = create(:orchestration_pipeline)
      step2 = create(:orchestration_step, pipeline: pipeline, position: 2)
      step1 = create(:orchestration_step, pipeline: pipeline, position: 1)
      expect(pipeline.steps_with_actions.to_a).to eq([ step1, step2 ])
    end

    it "eager loads each step's step_actions" do
      pipeline = create(:orchestration_pipeline)
      step = create(:orchestration_step, pipeline: pipeline)
      action = create(:orchestration_action, kind: :agent)
      create(:orchestration_step_action, step: step, action: action, position: 1)
      loaded_step = pipeline.steps_with_actions.to_a.first
      expect(loaded_step.step_actions).to be_loaded
    end
  end

  describe ".with_step_counts" do
    before do
      create(:orchestration_pipeline, name: "Alpha")
      pipeline_b = create(:orchestration_pipeline, name: "Bravo")
      pipeline_c = create(:orchestration_pipeline, name: "Charlie")
      create_list(:orchestration_step, 3, pipeline: pipeline_c)
      create(:orchestration_step, pipeline: pipeline_b)
    end

    it "returns the exact step_count per pipeline" do
      counts = described_class.with_step_counts.to_h { |p| [ p.name, p.step_count.to_i ] }
      expect(counts).to eq("Alpha" => 0, "Bravo" => 1, "Charlie" => 3)
    end

    it "orders pipelines by name" do
      expect(described_class.with_step_counts.map(&:name)).to eq(%w[Alpha Bravo Charlie])
    end
  end
end
