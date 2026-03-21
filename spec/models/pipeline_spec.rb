require 'rails_helper'

RSpec.describe Orchestration::Pipeline, type: :model do
  describe 'validations' do
    it 'is valid with required attributes' do
      pipeline = build(:orchestration_pipeline)
      expect(pipeline).to be_valid
    end

    it 'requires name' do
      pipeline = build(:orchestration_pipeline, name: nil)
      expect(pipeline).not_to be_valid
      expect(pipeline.errors[:name]).not_to be_empty
    end

    it 'defaults enabled to true' do
      pipeline = Orchestration::Pipeline.new(name: 'My Pipeline')
      expect(pipeline.enabled).to be true
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
end
