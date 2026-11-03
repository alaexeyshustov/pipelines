module TagPages
  class JobApplicationController < BaseController
    self.tag_name = "job_application"

    private

    def interview_columns?
      true
    end
  end
end
