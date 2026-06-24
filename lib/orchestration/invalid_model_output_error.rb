module Orchestration
  class InvalidModelOutputError < StandardError
    attr_reader :raw_content

    def initialize(message, raw_content:)
      @raw_content = raw_content
      super(message)
    end
  end
end
