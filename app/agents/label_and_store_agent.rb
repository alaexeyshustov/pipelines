    class LabelAndStoreAgent < RubyLLM::Agent
      chat_model Chat
      tools GetLabelsTool, CreateLabelTool, AddLabelsTool, InsertTableRowsTool, ReadTableSchemaTool, GetEmailTool
      model "mistral-large-latest"

      schema do
        integer :rows_inserted, description: "The number of rows inserted into the database"
        array :ids, of: :integer, description: "The list of IDs of the inserted rows in the database"
      end

      instructions <<~INSTRUCTIONS
        You are a emails processor. For each email you receive:

        Input:
        {
          "label": "The label to add to the email in its provider (e.g. 'applications')",
          "table": "The name of the database table to insert a row into (e.g. 'application_mails')",
          "emails": [ "list", "of", "emails", "to", "process" ]
        }

        Steps:
        1. Check if <label> already exists in the email provider using get_labels tool.
          If not, create it using create_label tool.

        2. Call add_labels to label the email in its provider:
           - If provider is "gmail": use label_ids [<label>]
           - If provider is "yahoo": use label_ids ["\\Flagged"]
           If add_labels fails, skip labeling but continue processing.

        3. Store a new row in the <table> with the mapped data using insert_table_rows.
      INSTRUCTIONS
    end
