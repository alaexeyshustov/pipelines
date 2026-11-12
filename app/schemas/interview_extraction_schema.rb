# Structured output of Interviews::EmailExtractor: what one job_application email says about one application.
# Per-email fields (id, provider, date) are not extracted; the Email row already carries them.
class InterviewExtractionSchema < Schematist::Schema
  ACTIONS = %w[apply notification interview offer rejection].freeze

  string :company, description: "Company name. Base this on combination of the subject and the email body content."
  string :job_title, description: <<~DESC.strip
    Job title. Base this on combination of the subject and the email body content.
    For example:
      - if the body says: We are confirming that we have received your application for the opportunity of (Senior) Backend Developer Ruby-on-Rails.
        Then the job_title should be "Senior Backend Developer Ruby-on-Rails". Action should be "apply" as this email confirms that the application was submitted.
      - If something like 'Ruby Developer (Kennenlernen via Google Meet)' is in the subject, then the job_title should be "Ruby Developer".
  DESC
  string :action, enum: ACTIONS, description: <<~DESC.strip
    The stage of the job application this email represents. Must be one of:
    - 'apply': confirmation that your application was received or submitted
    - 'notification': general update with no outcome (e.g. application under review, position filled with no decision on you)
    - 'interview': invitation or scheduling of any interview stage (phone screen, technical, onsite)
    - 'offer': a job offer extended to you
    - 'rejection': explicit statement that you were not selected or the position is no longer available to you
    Base this strictly on the email body content, not just the subject line.
  DESC
end
