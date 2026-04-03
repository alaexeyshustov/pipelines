require 'rails_helper'

RSpec.describe Orchestration::Pipeline do
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
end
