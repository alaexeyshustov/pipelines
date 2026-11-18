require "rails_helper"

RSpec.describe Emails::GmailAuth::CallbackReceiver do
  let(:server) { TCPServer.new("localhost", 0) }
  let(:port) { server.addr[1] }
  let(:receiver) { described_class.new(server:, state: "expected-state", timeout: 0.2) }

  after { server.close }

  # Bounds each example, so a receiver that blocks fails the spec instead of hanging the suite.
  def receive_code
    Timeout.timeout(5) { receiver.code }
  end

  it "times out on a client that connects and sends nothing" do
    client = TCPSocket.new("localhost", port)

    expect { receive_code }.to raise_error(Emails::GmailAuth::CallbackTimeout)
  ensure
    client&.close
  end

  it "raises a named error when the callback carries the right state but no code" do
    client = TCPSocket.new("localhost", port)
    client.write("GET /?state=expected-state HTTP/1.1\r\n\r\n")

    expect { receive_code }.to raise_error(Emails::GmailAuth::MissingCode)
  ensure
    client&.close
  end

  it "returns the code when the callback carries the right state" do
    client = TCPSocket.new("localhost", port)
    client.write("GET /?code=4%2Fabc&state=expected-state HTTP/1.1\r\n\r\n")

    expect(receive_code).to eq("4/abc")
  ensure
    client&.close
  end
end
