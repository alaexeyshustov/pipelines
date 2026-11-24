require "rails_helper"

RSpec.describe Orchestration::Executors::DocumentsClassify do
  it_behaves_like "a classify executor", factory: :document, key: :document_ids

  it "is registered as a pipeline service" do
    expect(Orchestration::ServiceRegistry.lookup("Orchestration::Executors::DocumentsClassify")).to eq(described_class)
  end
end
