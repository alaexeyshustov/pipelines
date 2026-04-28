module Evaluation
  class ToolStubRegistry
    def initialize(expected_tool_calls)
      @queues = Hash.new { |h, k| h[k] = [] } # steep:ignore
      expected_tool_calls.each do |tc|
        @queues[tc[:tool_name].to_s] << tc
      end
    end

    def lookup(tool_name:, arguments:)
      queue = @queues[tool_name.to_s]

      if queue.empty?
        Rails.logger.warn("ToolStubRegistry: no expected call for #{tool_name}")
        return nil
      end

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

      args.transform_keys(&:to_s).sort.to_h
    end
  end
end
