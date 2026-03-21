    class LabelAndStoreAgent < RubyLLM::Agent
      chat_model Chat
      tools GetLabelsTool, CreateLabelTool, AddLabelsTool, InsertTableRowsTool, ReadTableSchemaTool, GetEmailTool
      model "mistral-large-latest"

      schema do
        integer :rows_inserted, description: "The number of rows inserted into the database"
      end

      instructions <<~INSTRUCTIONS
        You are a emails processor. For each email you receive:

        Input:
        {
          "label": "The label to add to the email in its provider (e.g. 'applications')",
          "table": "The name of the database table to insert a row into (e.g. 'application_mails')",
          "emails": [
            {
              "id": "The email message ID",
              "subject": "The email subject line",
              "provider": "The email provider (e.g. 'gmail', 'yahoo')",
              "date": "The email date in ISO 8601 format",
              "from": "The email sender address",
              "tags": ["list", "of", "classification", "tags"] (e.g. ["job", "application"])
            }
          ]
        }

        Steps:
        1. Check if <label> already exists in the email provider using get_labels tool.
        If not, create it using create_label tool.

        2. Call add_labels to label the email in its provider:
           - If provider is "gmail": use label_ids [<label>]
           - If provider is "yahoo": use label_ids ["\\Flagged"]
           If add_labels fails, skip labeling but continue processing.

        3. Get a schema for the specified <table> and map email data to the appropriate columns. For example, for "application_mails" table, map to columns:
           - provider: from email.provider
           - email_id: from email.id
           - company: extracted from email.subject or set as "unknown"
           - job_title: extracted from email.subject or set as "unknown"
           - date: from email.date
           - sender: from email.from
           - tags: from email.tags (joined as a comma-separated string)
           - action: one word summarizing the email's meaning (e.g. "Applied", "Rejection", "Interview", "Offer", "Outreach", "Sent", "Followup")

        4. Store a new row in the <table> with the mapped data using insert_table_rows.
      INSTRUCTIONS
    end
