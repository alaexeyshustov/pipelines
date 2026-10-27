require "rails_helper"

RSpec.describe Emails::ConnectionTester do
  let(:yahoo_class) do
    Class.new do
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
    end
  end

  let(:gmail_class) do
    Class.new do
      class << self
        attr_accessor :env_args, :profile_requests
      end

      def self.from_env(opts = {})
        self.env_args = opts
        new
      end

      def initialize
        @service = Struct.new(:klass) do
          def get_user_profile(user) = klass.profile_requests = user
        end.new(self.class)
      end

      def on_init; end
    end
  end

  let(:providers) { { "yahoo" => yahoo_class, "gmail" => gmail_class } }

  describe "#call" do
    it "probes yahoo with the configuration and reports success" do
      config = { "host" => "localhost", "port" => "993", "username" => "u@yahoo.com", "password" => "pwd" }

      result = described_class.new(provider: "yahoo", configuration: config, providers:).call

      expect(result).to eq(success: true)
      expect(yahoo_class.init_args).to eq(host: "localhost", port: 993, username: "u@yahoo.com", password: "pwd")
    end

    it "returns the error message when the probe raises" do
      yahoo_class.error = StandardError.new("boom")

      result = described_class.new(provider: "yahoo", configuration: {}, providers:).call

      expect(result).to eq(success: false, error: "boom")
    end

    it "authorizes gmail and fetches the profile" do
      config = { "credentials_path" => "c.json", "token_path" => "t.yaml" }

      result = described_class.new(provider: "gmail", configuration: config, providers:).call

      expect(result).to eq(success: true)
      expect(gmail_class.env_args).to eq(credentials_path: "c.json", token_path: "t.yaml")
      expect(gmail_class.profile_requests).to eq("me")
    end

    it "reports an unknown provider" do
      result = described_class.new(provider: "aol", configuration: {}, providers:).call

      expect(result).to eq(success: false, error: "Unknown provider")
    end
  end
end
