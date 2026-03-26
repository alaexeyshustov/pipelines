class ApplicationMailsSchema < RubyLLM::Schema
  array :emails do
    string :email_id, description: "The unique ID of the email message from the provider."
    string :provider, description: "Email provider (e.g. gmail, yahoo) from which the email was received."
    string :date, description: "The date the email was received in ISO 8601 format."
    string :company, description: "Company name extracted from email subject or from email content."
    string :job_title, description: "Job title extracted from email subject or from email content."
    string :action, description: "One word summarizing the email's meaning. Possible values: 'apply', 'notification', 'interview', 'offer', 'rejection'."
  end
end
