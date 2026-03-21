class EmailFetchAgent < RubyLLM::Agent
  chat_model Chat
  tools ListEmailsTool, SearchEmailsTool, GetEmailTool, ManageTempFileTool
  model "mistral-large-latest"

  schema do
    array :results do
      object do
        string :id,       description: "The email message ID"
        string :subject,  description: "The email subject line"
        string :provider, description: 'The email provider (e.g. "gmail", "yahoo")'
        string :date,     description: "The email date in ISO 8601 format"
        string :from,     description: "The email sender address"
      end
    end
  end

  instructions <<~INSTRUCTIONS
    You are an email fetcher. Your job is to retrieve all emails from a given
    provider since a given date.

    Input:
    {
      "provider": "gmail" or "yahoo",
      "after_date": "YYYY-MM-DD",
      "before_date": "YYYY-MM-DD" (optional)
    }

    Steps:
    1. Call list_emails with the provider and after_date provided in the message,
        max_results: 100.
    2. If exactly 100 emails are returned, paginate: call list_emails again with
        offset: 100, then offset: 200, and so on until fewer than 100 are returned.
        Collect emails from all pages.

    If no emails are found, return an empty JSON array: []
  INSTRUCTIONS
end
