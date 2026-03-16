require "logger"

module Pipeline
  class Logger
    LEVELS = %w[debug info warn error].freeze

    class MultiIO
      def initialize(*targets)
        @targets = targets
      end

      def write(*args)
        @targets.each do |t|
          t.write(*args)
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

    LEVELS.each do |lvl|
      define_method(lvl) do |*args, &block|
        @logger.send(lvl, *args, &block)
      end
    end
  end
end
