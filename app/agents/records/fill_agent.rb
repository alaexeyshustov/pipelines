module Records
  class FillAgent < RubyLLM::Agent
    chat_model Chat
    tools Records::UpdateRowsTool, Emails::GetTool
    model "gpt-5.1"

    schema do
      integer :rows_updated, description: "The number of rows updated in the database"
    end

    instructions <<~INSTRUCTIONS
      Your task is to fill missing values in the <destination_table> table using the original email content.

      Input:
        {
          "emails": ["list", "of", "emails", "to", "process"],
          "destination_table": "The name of the database table to update.",
        }

      Steps:
      1. For each email in <emails>, always call get_email to fetch its full content — this is mandatory regardless of what fields appear to be populated.
      2. A field is considered missing if its value is null, an empty string, "unknown", "n/a", or any other clear placeholder.
      3. Call update_rows only for records where at least one field was successfully extracted. Skip records where nothing new was found.

    INSTRUCTIONS
  end
end
