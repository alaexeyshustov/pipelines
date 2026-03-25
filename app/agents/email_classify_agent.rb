class EmailClassifyAgent < RubyLLM::Agent
  chat_model Chat
  tools ManageTempFileTool
  model "mistral-large-latest"

  schema do
    array :results do
      object do
        string :id,   description: "The email message ID"
        array  :tags, of: :string, description: "Short lowercase classification tags"
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

    Steps:
    1. For each email, analyze the subject line and suggest short lowercase classification tags that are relevant to the content of the email. 
      Tags should be concise and descriptive (e.g. "job", "application", "interview", "offer").
  INSTRUCTIONS
end
