require "rails_helper"

# Real Google collaborators over a throwaway directory; only the token endpoint is stubbed (WebMock).
RSpec.describe Emails::GmailAuth do
  include_context "with gmail paths from env"

  let(:auth) do
    described_class.new(
      credentials_path: gmail_credentials_path, token_path: gmail_token_path,
      scope: Emails::Adapters::GmailSession::SCOPE, output:, **options
    )
  end

  let(:options) { {} }
  let(:output) { StringIO.new }
  let(:callback_uri) { "http://localhost:3000/settings/email_connectors/oauth_callback" }
  let(:token_url) { "https://oauth2.googleapis.com/token" }

  def file_mode(path) = File.stat(path).mode & 0o777

  before do
    stub_request(:post, token_url).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { access_token: "at", refresh_token: "rt", expires_in: 3600, token_type: "Bearer" }.to_json
    )
  end

  describe "#exchange_code" do
    it "creates the token file readable by the owner only" do
      auth.exchange_code(code: "4/abc", callback_uri:)

      expect(file_mode(gmail_token_path)).to eq(0o600)
    end

    it "tightens an existing world-readable token file" do
      File.write(gmail_token_path, "")
      File.chmod(0o644, gmail_token_path)

      auth.exchange_code(code: "4/abc", callback_uri:)

      expect(file_mode(gmail_token_path)).to eq(0o600)
    end

    it "does not change the process umask" do
      expect { auth.exchange_code(code: "4/abc", callback_uri:) }.not_to change(File, :umask)
    end
  end

  describe "#credentials" do
    it "tightens an existing world-readable token file before reading it" do
      File.write(gmail_token_path, "")
      File.chmod(0o644, gmail_token_path)

      expect { auth.credentials }.to raise_error(Emails::NotConfigured)

      expect(file_mode(gmail_token_path)).to eq(0o600)
    end
  end

  describe "#authorization_url" do
    it "includes the given state" do
      url = auth.authorization_url(callback_uri:, state: "csrf-token")

      expect(Rack::Utils.parse_query(URI(url).query)["state"]).to eq("csrf-token")
    end
  end

  describe "#credentials(interactive: true) loopback" do
    # Collects the lines the flow prints and lets the example wait for the authorization URL without sleeping.
    let(:output) do
      stub_const("QueueOutput", Class.new do
        attr_reader :lines

        def initialize
          @lines = Queue.new
        end

        def puts(line)
          @lines << line.to_s
        end
      end).new
    end

    let(:accept_timeout) { 2 }
    let(:options) { { accept_timeout: } }

    before do
      allow(auth).to receive_messages(interactive_authorization_allowed?: true, open_authorization_url: true)
    end

    def run_flow
      thread = Thread.new { auth.credentials(interactive: true) }
      thread.report_on_exception = false
      params = Rack::Utils.parse_query(URI(await_authorization_url(thread)).query)
      [ thread, params["state"], URI(params["redirect_uri"]).port ]
    end

    # Bounded: fails instead of looping when the flow prints nothing more.
    def await_authorization_url(thread)
      loop do
        line = output.lines.pop(timeout: 5)
        return line if line&.start_with?("https://accounts.google.com")
        next if line

        thread.join(1) # re-raises the flow's error when it died before printing the URL
        raise "No authorization URL printed within 5 seconds"
      end
    end

    def send_callback(port, query)
      client = TCPSocket.new("localhost", port)
      client.write("GET /?#{query} HTTP/1.1\r\nHost: localhost\r\n\r\n")
      client.close
    end

    context "when nobody calls back" do
      let(:accept_timeout) { 0.1 }

      it "uses a random state per run" do
        first_thread, first, = run_flow
        second_thread, second, = run_flow

        expect([ first, second ]).to all(be_present)
        expect(first).not_to eq(second)
        [ first_thread, second_thread ].each { |thread| expect { thread.value }.to raise_error(described_class::CallbackTimeout) }
      end

      it "times out waiting for the browser, raises a named error and closes the server" do
        thread, _state, port = run_flow

        expect { thread.value }.to raise_error(described_class::CallbackTimeout)
        expect { TCPSocket.new("localhost", port).close }.to raise_error(Errno::ECONNREFUSED)
      end
    end

    it "returns the stored credentials when the callback carries the right state" do
      thread, state, port = run_flow
      send_callback(port, "code=4%2Fabc&state=#{state}")

      expect(thread.value).to be_a(Signet::OAuth2::Client)
      expect(a_request(:post, token_url).with(body: hash_including("code" => "4/abc"))).to have_been_made
      expect(file_mode(gmail_token_path)).to eq(0o600)
    end

    it "rejects a callback with a wrong state and never exchanges the code" do
      thread, _state, port = run_flow
      send_callback(port, "code=4%2Fabc&state=forged")

      expect { thread.value }.to raise_error(described_class::InvalidState)
      expect(a_request(:post, token_url)).not_to have_been_made
      expect { TCPSocket.new("localhost", port).close }.to raise_error(Errno::ECONNREFUSED)
    end

    it "rejects a callback without a state and never exchanges the code" do
      thread, _state, port = run_flow
      send_callback(port, "code=4%2Fabc")

      expect { thread.value }.to raise_error(described_class::InvalidState)
      expect(a_request(:post, token_url)).not_to have_been_made
    end
  end
end
