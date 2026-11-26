require "rails_helper"

RSpec.describe Orchestration::Executors::EmailsClassify do
  it_behaves_like "a classify executor", factory: :email, key: :email_ids

  it "is registered as a pipeline service" do
    expect(Orchestration::ServiceRegistry.lookup("Orchestration::Executors::EmailsClassify")).to eq(described_class)
  end
end
