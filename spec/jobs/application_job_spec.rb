require "rails_helper"

RSpec.describe ApplicationJob do
  describe ".logger" do
    it "writes to a dedicated active job log file" do
      job_log_path = Rails.root.join("log", "#{Rails.env}_active_job.log").to_s
      job_logger_path = described_class.logger.instance_variable_get(:@logdev)&.filename.to_s

      expect(job_logger_path).to eq(job_log_path)
    end

    it "does not write to the main Rails log file" do
      job_log_path = Rails.root.join("log", "#{Rails.env}_active_job.log").to_s
      rails_log_paths = Rails.logger.broadcasts.filter_map { |l| l.instance_variable_get(:@logdev)&.filename.to_s }

      expect(rails_log_paths).not_to include(job_log_path)
    end
  end
end
