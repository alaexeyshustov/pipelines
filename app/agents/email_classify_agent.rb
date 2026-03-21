class EmailClassifyAgent < RubyLLM::Agent
  chat_model Chat
  tools ManageTempFileTool
  model "mistral-large-latest"

  schema do
    array :results do
      object do
        string :id,       description: "The email message ID"
        string :subject,  description: "The email subject line"
        array :tags,      description: "Short lowercase classification tags", of: :string
      end
    end
  end

  instructions <<~INSTRUCTIONS
    You are an email classifier. Your job is to tag a list of emails by their subject lines and return suggested tags.

    Input:
    {
      "emails": [
        {"id": "id of email", "subject": "Email subject line"}
      ]
    }

    If no emails are found, return an empty JSON array: []
  INSTRUCTIONS
end
