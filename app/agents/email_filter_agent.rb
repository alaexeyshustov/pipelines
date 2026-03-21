class EmailFilterAgent < RubyLLM::Agent
  chat_model Chat
  model "mistral-large-latest"
  tools ClassifyEmailsTool, ManageTempFileTool

  schema do
    array :results do
      object do
        string :id,   description: "The email message ID"
        string :subject, description: "The email subject line"
        string :provider, description: 'The email provider (e.g. "gmail", "yahoo")'
        string :date, description: "The email date in ISO 8601 format"
        string :from, description: "The email sender address"
        array  :tags, of: :string, description: "Short lowercase classification tags"
      end
    end
  end

  instructions <<~INSTRUCTIONS
    You are an email filtering expert. Your job is to identify <emails> from a list related to a <topic>.

    Input:
    {
      "topic": "The topic to filter by (e.g. 'job applications')",
      "emails": [
        {"id": "id of email", "subject": "Email subject line", "provider": "gmail or yahoo", "date": "YYYY-MM-DD", "from": "Email sender address"}
      ]
    }

    Steps:
    1. Call classify_emails in batches of up to 20 emails at a time.
    2. Collect all classification results.
    3. Return ONLY emails tagged with ANY of tags related to the <topic>
      (e.g. for "job applications" topic, tags might include "job", "application", "interview", "offer", etc.).

    If no emails related to the <topic> are found, return an empty JSON array: []
  INSTRUCTIONS
end
