module Emails
  class TestConnectionService
    def self.call(connector:) = new(connector:).call

    def initialize(connector:)
      @connector = connector
    end

    def call
      outcome = Emails::ConnectionTester.new(provider: @connector.provider, configuration: @connector.configuration).call
      record_outcome(outcome)
      outcome
    end

    private

    def record_outcome(outcome)
      return if outcome[:error] == Emails::ConnectionTester::UNKNOWN_PROVIDER

      if outcome[:success]
        @connector.update(status: "connected", last_connected_at: Time.current)
      else
        @connector.update(status: "failed")
      end
    end
  end
end
