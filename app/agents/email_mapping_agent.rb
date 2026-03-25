class EmailMappingAgent < RubyLLM::Agent
  chat_model Chat
  model "mistral-large-latest"
  tools GetEmailTool, ManageTempFileTool

  instructions <<~INSTRUCTIONS
    Your task is to map raw email data to a structured format for database insertion.

    Input:
    {
      "emails": ["list", "of", "emails", "to", "process"],
    }

    Steps:
    1. For each email in <emails> map the raw email data to a structured format with the fields.
    2. When information is missing, use the get_email tool to read the original email content and extract the missing information if possible.

  INSTRUCTIONS
end
