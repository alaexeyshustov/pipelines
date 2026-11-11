require "rails_helper"

RSpec.describe Orchestration::Executors::DriveDocumentsSync do
  describe ".call" do
    it "runs the Drive sync job inline and returns its summary" do
      summary = { "created" => 1, "updated" => 0, "unchanged" => 2, "deleted" => 0, "failed" => 0 }
      allow(Document::SyncDriveJob).to receive(:perform_now).and_return(summary)

      expect(described_class.call).to eq(summary)
    end

    it "declares no inputs" do
      expect(described_class.input_schema).to be_nil
    end
  end

  it "is registered as a pipeline service" do
    expect(Orchestration::ServiceRegistry.lookup("Orchestration::Executors::DriveDocumentsSync")).to eq(described_class)
  end
end
