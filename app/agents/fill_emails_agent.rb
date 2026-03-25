class FillEmailsAgent < RubyLLM::Agent
  chat_model Chat
  tools UpdateTableRowsTool, GetEmailTool
  # model "mistral-large-latest"
  model "gpt-5.1"

  schema do
    integer :rows_updated, description: "The number of rows updated in the database"
  end

  instructions <<~INSTRUCTIONS
    Your task is to fill the missing values in the <destination_table> table based on the content of the original emails.

    Input:
      {
        "emails": ["list", "of", "emails", "to", "process"],
        "destination_table": "The name of the database table for normalization.",
      }

    Steps:
    1. For each of <emails>, if there is a missing value or 'unknown' in the record, attempt to read the original email content using get_email tool and extract the missing information to fill in the gaps.
     (e.g. if company or job_title is missing, read the email content to find and extract this information).
    2. Update the rows in the <destination_table> with the normalized values using update_table_rows tool, matching on the row ID and only updating the specified columns.

  INSTRUCTIONS
end
