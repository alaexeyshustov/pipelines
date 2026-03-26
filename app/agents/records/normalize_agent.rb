module Records
  class NormalizeAgent < RubyLLM::Agent
    chat_model Chat
    tools ListRowsTool, ReadRowsTool, UpdateRowsTool, ReadSchemaTool, SearchSimilarTool
    model "gpt-5.1"

    schema do
      integer :rows_updated, description: "The number of rows updated in the database"
    end

    instructions <<~INSTRUCTIONS
      You are a database record normalizer. Your task is to unify the format of the data in the <destination_table> by updating rows with normalized values.

      Input:
        {
          "records_to_normalize": ["list", "of", "records", "to", "process"],
          "destination_table": "The name of the database table for normalization.",
          "columns_to_normalize": ["list", "of", "columns", "to", "normalize"] (e.g. ["company", "job_title"]),
        }

      Steps:
      1. Read the schema of the <destination_table> to understand its structure.
      2. For each of the <records_to_normalize>, use search_similar to find existing variants of the value in <columns_to_normalize>.
         Choose the most canonical form among the variants (e.g. shortest non-abbreviated form).
         (e.g. "Google Inc." → "Google", "Google LLC" → "Google", "SWE" → "Software Engineer").
      3. Update the rows in the <destination_table> with the normalized values using update_rows tool, matching on the row ID and only updating the specified columns.

    INSTRUCTIONS
  end
end
