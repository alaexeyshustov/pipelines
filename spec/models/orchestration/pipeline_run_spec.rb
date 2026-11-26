require 'rails_helper'

RSpec.describe Orchestration::PipelineRun do
  it { expect(described_class.table_name).to eq("orchestration_pipeline_runs") }

  describe 'validations' do
    it 'is valid with required attributes' do
      run = build(:orchestration_pipeline_run)
      expect(run).to be_valid
    end

    it_behaves_like 'requires attribute', :status, :orchestration_pipeline_run
    it_behaves_like 'rejects invalid attribute value', :status, :orchestration_pipeline_run, 'invalid'
    it_behaves_like 'accepts valid statuses', :orchestration_pipeline_run, %w[pending running completed failed]
    it_behaves_like 'rejects invalid attribute value', :triggered_by, :orchestration_pipeline_run, 'robot'

    it 'accepts nil triggered_by' do
      run = build(:orchestration_pipeline_run, triggered_by: nil)
      expect(run).to be_valid
    end

    it 'contains expected STATUSES' do
      expect(Orchestration::PipelineRun::STATUSES).to eq(%w[pending running completed failed])
    end

    it 'contains expected ACTIVE_STATUSES' do
      expect(Orchestration::PipelineRun::ACTIVE_STATUSES).to eq(%w[pending running])
    end
  end

  describe '.recent_first' do
    it 'orders runs newest first by created_at' do
      older = create(:orchestration_pipeline_run, created_at: 2.days.ago)
      newer = create(:orchestration_pipeline_run, created_at: 1.hour.ago)
      expect(described_class.recent_first.to_a).to eq([ newer, older ])
    end
  end

  describe '.in_progress' do
    it 'returns pending and running runs and excludes completed and failed' do
      pending = create(:orchestration_pipeline_run, status: 'pending')
      running = create(:orchestration_pipeline_run, status: 'running')
      completed = create(:orchestration_pipeline_run, status: 'completed')
      failed = create(:orchestration_pipeline_run, status: 'failed')
      result = described_class.in_progress.to_a
      expect(result).to include(pending, running)
      expect(result).not_to include(completed, failed)
    end
  end

  describe 'STALE_AFTER' do
    it 'is 10 minutes' do
      expect(described_class::STALE_AFTER).to eq(10.minutes)
    end
  end

  describe '.blocking' do
    it 'includes an in-progress run with a recent heartbeat, however old it started' do
      run = create(:orchestration_pipeline_run, status: 'running', started_at: 3.hours.ago, heartbeat_at: 2.minutes.ago)
      expect(described_class.blocking).to include(run)
    end

    it 'excludes an in-progress run whose heartbeat is older than STALE_AFTER, however recently it started' do
      run = create(:orchestration_pipeline_run, status: 'running', started_at: 1.minute.ago, heartbeat_at: 11.minutes.ago)
      expect(described_class.blocking).not_to include(run)
    end

    it 'falls back to started_at when there is no heartbeat' do
      recent = create(:orchestration_pipeline_run, status: 'running', started_at: 5.minutes.ago)
      stale = create(:orchestration_pipeline_run, status: 'running', started_at: 11.minutes.ago)
      expect(described_class.blocking).to include(recent)
      expect(described_class.blocking).not_to include(stale)
    end

    it 'falls back to created_at when there is neither a heartbeat nor started_at' do
      recent = create(:orchestration_pipeline_run, status: 'pending', created_at: 5.minutes.ago)
      stale = create(:orchestration_pipeline_run, status: 'pending', created_at: 11.minutes.ago)
      expect(described_class.blocking).to include(recent)
      expect(described_class.blocking).not_to include(stale)
    end

    it 'prefers the heartbeat to started_at and created_at' do
      run = create(:orchestration_pipeline_run, status: 'running', created_at: 2.hours.ago, started_at: 2.hours.ago, heartbeat_at: 1.minute.ago)
      expect(described_class.blocking).to include(run)
    end

    it 'excludes completed and failed runs even with a recent heartbeat' do
      done = create(:orchestration_pipeline_run, status: 'completed', heartbeat_at: 1.minute.ago)
      failed = create(:orchestration_pipeline_run, status: 'failed', heartbeat_at: 1.minute.ago)
      expect(described_class.blocking).not_to include(done, failed)
    end

    it 'is a relation that composes with where' do
      pipeline = create(:orchestration_pipeline)
      mine = create(:orchestration_pipeline_run, pipeline:, status: 'running', heartbeat_at: 1.minute.ago)
      create(:orchestration_pipeline_run, status: 'running', heartbeat_at: 1.minute.ago)
      expect(described_class.where(pipeline:).blocking).to eq([ mine ])
    end
  end

  describe 'heartbeat_at' do
    it 'is nil until a run beats' do
      expect(create(:orchestration_pipeline_run).heartbeat_at).to be_nil
    end
  end

  describe 'associations' do
    it 'destroys action_runs when pipeline_run is destroyed' do
      pipeline_run = create(:orchestration_pipeline_run)
      step = create(:orchestration_step)
      step_action = create(:orchestration_step_action, step: step, position: 1)
      create(:orchestration_action_run, pipeline_run: pipeline_run, step_action: step_action)
      expect { pipeline_run.destroy }.to change(Orchestration::ActionRun, :count).by(-1)
    end
  end
end
