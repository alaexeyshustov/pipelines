require "rails_helper"

RSpec.describe ApplicationJob do
  describe ".logger" do
    it "writes to a dedicated active job log file" do
      job_log_paths = [ described_class.logger.instance_variable_get(:@logdev)&.filename ].compact.map(&:to_s)

      expect(job_log_paths).to include(Rails.root.join("log", "#{Rails.env}_active_job.log").to_s)
      expect(job_log_paths).not_to eq(Rails.logger.broadcasts.map { |logger| logger.instance_variable_get(:@logdev)&.filename }.compact)
    end
  end
end
