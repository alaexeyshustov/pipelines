class ApplicationMailsSchema < RubyLLM::Schema
  array :emails do
    object do
      string :email_id, description: "The unique ID of the email message from the provider."
      string :provider, description: "Email provider (e.g. gmail, yahoo) from which the email was received."
      string :date, description: "The date the email was received in ISO 8601 format."
      string :company, description: "Company name. Base this on combination of the subject and the email body content."
      string :job_title, description: <<~DESC.strip
        Job title. Base this on combination of the subject and the email body content.
        For example:
          - if the body says: We are confirming that we have received your application for the opportunity of (Senior) Backend Developer Ruby-on-Rails.
            Then the job_title should be "Senior Backend Developer Ruby-on-Rails". Action should be "apply" as this email confirms that the application was submitted.
          - If something like 'Ruby Developer (Kennenlernen via Google Meet)' is in the subject, then the job_title should be "Ruby Developer".
      DESC
      string :action, description: <<~DESC.strip
        The stage of the job application this email represents. Must be one of:
        - 'apply': confirmation that your application was received or submitted
        - 'notification': general update with no outcome (e.g. application under review, position filled with no decision on you)
        - 'interview': invitation or scheduling of any interview stage (phone screen, technical, onsite)
        - 'offer': a job offer extended to you
        - 'rejection': explicit statement that you were not selected or the position is no longer available to you
        Base this strictly on the email body content, not just the subject line.
      DESC
    end
  end
end
