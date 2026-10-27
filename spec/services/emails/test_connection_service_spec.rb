require "rails_helper"

RSpec.describe Emails::TestConnectionService do
  let(:connector) { EmailConnector.create!(name: "Y", provider: "yahoo", configuration: { host: "h", port: 993 }) }

  def stub_tester(outcome)
    tester = Class.new do
      define_method(:call) { outcome }
    end.new
    allow(Emails::ConnectionTester).to receive(:new).and_return(tester)
  end

  it "marks the connector connected on success" do
    stub_tester({ success: true })

    result = described_class.call(connector:)

    expect(result).to eq(success: true)
    expect(connector.reload).to have_attributes(status: "connected", last_connected_at: be_present)
  end

  it "marks the connector failed and returns the error" do
    stub_tester({ success: false, error: "nope" })

    result = described_class.call(connector:)

    expect(result).to eq(success: false, error: "nope")
    expect(connector.reload.status).to eq("failed")
  end

  it "leaves status untouched for an unknown provider" do
    stub_tester({ success: false, error: Emails::ConnectionTester::UNKNOWN_PROVIDER })

    described_class.call(connector:)

    expect(connector.reload.status).to be_nil
  end
end
