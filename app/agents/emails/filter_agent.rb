module Emails
  class FilterAgent < RubyLLM::Agent
    chat_model Chat
    model "mistral-large-latest"
    tools Records::TempFileTool

    schema do
      array :results do
        object do
          string :id,   description: "The email message ID"
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
          {"id": "id of email", "subject": "Email subject line", "tags": ["list", "of", "classification", "tags"] }
        ]
      }

      Steps:
      3. Return ONLY emails tagged with ANY of tags related to the <topic>
        (e.g. for "job applications" topic, tags might include "job", "application", "interview", "offer", etc.).

      If no emails related to the <topic> are found, return an empty JSON array: []
    INSTRUCTIONS
  end
end
