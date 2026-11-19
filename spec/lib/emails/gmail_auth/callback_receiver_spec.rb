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

  context "when the browser hangs up before the reply is written" do
    # A connection whose writes fail the way a closed peer's do (EPIPE on Linux).
    let(:closed_peer) do
      stub_const("ClosedPeer", Class.new do
        def initialize(request_line) = @request_line = request_line
        def wait_readable(_timeout) = true
        def gets(_limit) = @request_line
        def print(*) = raise(Errno::EPIPE)
        def close = nil
      end)
    end
    let(:fake_server) do
      stub_const("OnePeerServer", Class.new do
        def initialize(peer) = @peer = peer
        def wait_readable(_timeout) = true
        def accept = @peer
      end)
    end

    def receive_from(request_line)
      server = fake_server.new(closed_peer.new(request_line))
      described_class.new(server:, state: "expected-state", timeout: 0.2).code
    end

    it "still returns the code" do
      expect(receive_from("GET /?code=4%2Fabc&state=expected-state HTTP/1.1\r\n")).to eq("4/abc")
    end

    it "still raises InvalidState for a forged state" do
      expect { receive_from("GET /?code=4%2Fabc&state=forged HTTP/1.1\r\n") }
        .to raise_error(Emails::GmailAuth::InvalidState)
    end
  end
end
