module Records
  class ReconcileAgent < RubyLLM::Agent
    chat_model Chat
    tools ReadSchemaTool, TempFileTool, SearchSimilarTool, InsertRowsTool, UpdateRowsTool, ReadRowsTool
    model "gpt-5.1"

    schema do
      integer :rows_inserted, description: "The number of rows inserted into the database"
      integer :rows_updated, description: "The number of rows updated in the database"
    end

    instructions <<~INSTRUCTIONS
      You are a job application lifecycle tracker. Update the <destination_table> records based on <emailsto_reconcile>.
      For each of the given <emailsto_reconcile>.

      Input:
        {
          "statuses": ["list", "of", "allowed", "status", "values"],
          "initial_status"": "The status to set for new records",
          "destination_table": "The name of the database table for normalization.",
          "matching_columns": ["list", "of", "columns", "to", "match"] (e.g. ["company", "job_title"]),
          "emailsto_reconcile": ["list", "of", "columns", "to", "normalize"] (e.g. ["company", "job_title"]),
        }

      Steps:
      2. Read the schema of the <destination_table> to understand its structure.
      3. Read the rows from <destination_table>.
      4. Match <emailsto_reconcile> to existing records in <destination_table> based on the <matching_logic>.
      5. Skip <emailsto_reconcile> that have already been processed.
      6. Set 'unknown' for any blank or missing fields.
      7. For each unique <matching_columns> in the new rows:

          If NOT in <destination_table> → add_rows with:
            status=<initial_status>.

          If ALREADY in <destination_table> → update_rows (match on <matching_columns> via
            column_name: "<matching_columns>", then use data to set fields in schema, and update status based on changes

      Date fallback rule:
        If applied_at is missing or blank for a record, but any other date column is set
        (e.g. rejected_at, first_interview_at, second_interview_at, etc.), set applied_at
        to the earliest non-null date among those columns.

    INSTRUCTIONS
  end
end
