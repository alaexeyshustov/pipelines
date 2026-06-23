require "logger"

module Pipeline
  class Logger
    class MultiIO
      def initialize(*targets)
        @targets = targets
      end

      def write(message)
        string_message = message.to_s
        @targets.each do |t|
          t.write(string_message)
          t.flush if t.respond_to?(:flush)
        end
      end

      def flush
        @targets.each { |t| t.flush if t.respond_to?(:flush) }
      end

      def close
        @targets.each(&:close)
      end
    end

    def initialize(level: :info, output: $stderr, log_file: nil)
      dest = if log_file
               MultiIO.new(output, File.open(log_file, "a"))
      else
               output
      end
      @logger           = ::Logger.new(dest)
      @logger.level     = ::Logger.const_get(level.to_s.upcase)
      @logger.formatter = proc do |severity, _time, _prog, msg|
        "[Pipeline] [#{severity}] #{msg}\n"
      end
    end

    def debug(message = nil, &block) = @logger.debug(message, &block)
    def debug?                       = @logger.debug?
    def info(message = nil, &block)  = @logger.info(message, &block)
    def info?                        = @logger.info?
    def warn(message = nil, &block)  = @logger.warn(message, &block)
    def warn?                        = @logger.warn?
    def error(message = nil, &block) = @logger.error(message, &block)
    def error?                       = @logger.error?
  end
end
