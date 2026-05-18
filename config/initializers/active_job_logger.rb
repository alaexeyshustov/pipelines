# frozen_string_literal: true

active_job_logger = ActiveSupport::Logger.new(Rails.root.join("log", "#{Rails.env}_active_job.log"))
active_job_logger.level = Rails.logger.level
active_job_logger.formatter = ::Logger::Formatter.new

ActiveJob::Base.logger = ActiveSupport::TaggedLogging.new(active_job_logger)
