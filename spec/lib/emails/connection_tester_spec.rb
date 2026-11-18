require "rails_helper"

RSpec.describe Emails::ConnectionTester do
  let(:yahoo_class) do
    stub_const("FakeYahooClient", Class.new do
      class << self
        attr_accessor :init_args, :error
      end

      def self.from_env(opts = {})
        self.init_args = opts
        new
      end

      def list_messages(max_results:) # rubocop:disable Lint/UnusedMethodArgument
        raise self.class.error if self.class.error

        []
      end
    end)
  end

  # Like GmailAdapter.from_env, from_env returns an already authorized adapter.
  let(:gmail_class) do
    stub_const("FakeGmailClient", Class.new do
      class << self
        attr_accessor :env_args, :profile_calls, :init_calls, :error
      end

      def self.from_env(opts = {})
        self.env_args = opts
        raise error if error

        new
      end

      def on_init
        self.class.init_calls = self.class.init_calls.to_i + 1
      end

      def profile
        self.class.profile_calls = self.class.profile_calls.to_i + 1
        { email_address: "me@gmail.com", history_id: "1" }
      end
    end)
  end

  let(:providers) { { "yahoo" => yahoo_class, "gmail" => gmail_class } }

  describe "#call" do
    it "probes yahoo with only the username and password and reports success" do
      config = { "host" => "localhost", "port" => "993", "username" => "u@yahoo.com", "password" => "pwd" }

      result = described_class.new(provider: "yahoo", configuration: config, providers:).call

      expect(result).to eq(success: true)
      expect(yahoo_class.init_args).to eq(username: "u@yahoo.com", password: "pwd")
    end

    it "ignores a configured host and port so the endpoint is never chosen by the caller" do
      config = { "host" => "attacker.example", "port" => "25", "username" => "u", "password" => "p" }

      described_class.new(provider: "yahoo", configuration: config, providers:).call

      expect(yahoo_class.init_args.keys).to contain_exactly(:username, :password)
    end

    it "returns a generic error and the exception when the probe raises" do
      error = StandardError.new("boom")
      yahoo_class.error = error

      result = described_class.new(provider: "yahoo", configuration: { "username" => "u", "password" => "p" }, providers:).call

      expect(result).to include(success: false, exception: error)
      expect(result[:error]).to be_present
      expect(result[:error]).not_to include("boom")
    end

    [
      [ "no configuration", {} ],
      [ "a blank password", { "username" => "u@yahoo.com", "password" => "" } ],
      [ "no username", { "password" => "pwd" } ]
    ].each do |description, config|
      it "fails yahoo with #{description} without probing, so the server's own account is never used" do
        result = described_class.new(provider: "yahoo", configuration: config, providers:).call

        expect(result).to include(success: false, error: described_class::GENERIC_ERROR)
        expect(result[:exception]).to be_a(Emails::NotConfigured)
        expect(yahoo_class.init_args).to be_nil
      end
    end

    it "does not leak server paths from a gmail failure" do
      gmail_class.error = Emails::NotConfigured.new("Missing Gmail credentials file /srv/secret/credentials.json")

      result = described_class.new(provider: "gmail", configuration: {}, providers:).call

      expect(result[:success]).to be(false)
      expect(result[:error]).not_to include("/srv/secret")
      expect(result[:exception]).to be_a(Emails::NotConfigured)
    end

    it "authorizes gmail from server config only and fetches the profile" do
      config = { "credentials_path" => "/etc/passwd", "token_path" => "/tmp/t.yaml" }

      result = described_class.new(provider: "gmail", configuration: config, providers:).call

      expect(result).to eq(success: true)
      expect(gmail_class.env_args).to eq({})
      expect(gmail_class.profile_calls).to eq(1)
    end

    it "does not authorize gmail a second time" do
      described_class.new(provider: "gmail", configuration: {}, providers:).call

      expect(gmail_class.init_calls).to be_nil
    end

    it "reports an unknown provider" do
      result = described_class.new(provider: "aol", configuration: {}, providers:).call

      expect(result).to eq(success: false, error: "Unknown provider")
    end
  end
end
