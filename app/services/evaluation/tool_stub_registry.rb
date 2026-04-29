module Evaluation
  class ToolStubRegistry
    ToolStubError = Class.new(StandardError)

    def initialize(expected_tool_calls)
      @queues = Hash.new { |h, k| h[k] = [] } # steep:ignore
      expected_tool_calls.each do |tc|
        @queues[tc[:tool_name].to_s] << tc
      end
    end

    def lookup(tool_name:, arguments:)
      queue = @queues[tool_name.to_s]

      raise ToolStubError, "ToolStubRegistry: no expected call for #{tool_name}" if queue.empty?

      expected = queue.shift
      normalized_expected = normalize(expected[:arguments])
      normalized_actual = normalize(arguments)

      unless normalized_expected == normalized_actual
        Rails.logger.warn(
          "ToolStubRegistry mismatch for #{tool_name}: " \
          "expected #{normalized_expected.inspect}, got #{normalized_actual.inspect}"
        )
      end

      expected[:result]
    end

    private

    def normalize(args)
      return {} if args.nil?

      JSON.parse(args.transform_keys(&:to_s).to_json)
    end
  end
end
