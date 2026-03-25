module Records
  class ReconcileAgent < RubyLLM::Agent
    chat_model Chat
    tools ReadRowsTool, InsertRowsTool, UpdateRowsTool, ReadSchemaTool, TempFileTool
    model "gpt-5.1"

    schema do
      integer :rows_inserted, description: "The number of rows inserted into the database"
      integer :rows_updated, description: "The number of rows updated in the database"
    end

    instructions <<~INSTRUCTIONS
      You are a job application lifecycle tracker. Update the <destination_table> records based on <emailsto_reconcile>.
      For each of the given <emailsto_reconcile>.

      Status values: <statuses>

      Steps:
      2. Read the schema of the <destination_table> to understand its structure.
      3. Read the rows from <destination_table>.
      4. Match <emailsto_reconcile> to existing records in <destination_table> based on the <matching_logic>.
      5. Skip <emailsto_reconcile> that have already been processed.
      6. For each unique <matching_columns> in the new rows:

          If NOT in <destination_table> → add_rows with:
            status=<initial_status>.

          If ALREADY in <destination_table> → update_rows (match on <matching_columns> via
            column_name: "<matching_columns>", then use data to set fields in schema, and update status based on changes

    INSTRUCTIONS
  end
end
