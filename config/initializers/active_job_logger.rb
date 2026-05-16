# frozen_string_literal: true

source_logger = Rails.logger.broadcasts.first || Rails.logger
active_job_logger = ActiveSupport::Logger.new(Rails.root.join("log", "#{Rails.env}_active_job.log"))
active_job_logger.level = Rails.logger.level
active_job_logger.formatter = source_logger.formatter.clone if source_logger.formatter

ActiveJob::Base.logger = ActiveSupport::TaggedLogging.new(active_job_logger)
