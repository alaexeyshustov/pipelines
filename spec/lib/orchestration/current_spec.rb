require "rails_helper"

RSpec.describe Orchestration::Current do
  after { described_class.reset }

  it "is ActiveSupport::CurrentAttributes holding the pipeline run being executed" do
    expect(described_class.ancestors).to include(ActiveSupport::CurrentAttributes)
    run = build_stubbed(:orchestration_pipeline_run)

    described_class.pipeline_run = run

    expect(described_class.pipeline_run).to eq(run)
  end

  it "is empty after reset" do
    described_class.pipeline_run = build_stubbed(:orchestration_pipeline_run)

    described_class.reset

    expect(described_class.pipeline_run).to be_nil
  end
end
