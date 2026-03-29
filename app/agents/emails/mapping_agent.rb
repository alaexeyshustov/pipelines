module Emails
  class MappingAgent < RubyLLM::Agent
    chat_model Chat
    model "mistral-large-latest"
    tools GetTool, Records::TempFileTool

    instructions <<~INSTRUCTIONS
      Your task is to map raw email data to a structured format for database insertion.

      Input:
      {
        "emails": ["list", "of", "emails", "to", "process"],
      }

      Steps:
      1. For each email in <emails>, call get_email to fetch its full content — this is mandatory before mapping any field.
      2. After reading the full email content, extract and map all required fields.
      3. Base the "action" field strictly on the email body text, not just the subject line.

    INSTRUCTIONS
  end
end
