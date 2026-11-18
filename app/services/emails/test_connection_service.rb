module Emails
  class TestConnectionService
    Result = Data.define(:success, :error)
    class Result
      def success? = success
    end

    def self.call(connector:) = new(connector:).call

    def initialize(connector:)
      @connector = connector
    end

    def call
      outcome = Emails::ConnectionTester.new(provider: @connector.provider, configuration: @connector.configuration).call
      log_exception(outcome[:exception])
      record_outcome(outcome)
      Result.new(success: outcome[:success], error: outcome[:error])
    end

    private

    def log_exception(exception)
      return unless exception

      Rails.logger.error { "Connection test failed for connector #{@connector.id}: #{exception.class}: #{exception.message}" }
    end

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
