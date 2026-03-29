module Records
  class NormalizeAgent < RubyLLM::Agent
    chat_model Chat
    tools ListRowsTool, ReadRowsTool, UpdateRowsTool, ReadSchemaTool, SearchSimilarTool
    model "gpt-5.1"

    schema do
      integer :rows_updated, description: "The number of rows updated in the database"
    end

    instructions <<~INSTRUCTIONS
      You are a database record normalizer. Your task is to unify the format of the data in the <destination_table> and propagate known values to records where they are missing.

      Input:
        {
          "records_to_normalize": ["list", "of", "records", "to", "process"],
          "destination_table": "The name of the database table for normalization.",
          "columns_to_normalize": ["list", "of", "columns", "to", "normalize"] (e.g. ["company", "job_title"]),
        }

      A field is considered missing if its value is null, an empty string, "unknown", "n/a", or any other placeholder.

      Steps:
      1. Read the schema of the <destination_table> to understand its structure.
      2. For each record in <records_to_normalize>, for each column in <columns_to_normalize>:
         a. If the field is populated: use search_similar to find all variant spellings of that value in the table.
            Choose the most canonical form among the variants (e.g. shortest non-abbreviated, non-suffixed form).
            (e.g. "Google Inc." → "Google", "SWE" → "Software Engineer").
         b. If the field is missing: look at the record's other populated columns (e.g. company when job_title is missing, or vice versa)
            and call search_similar on those to find sibling records that share the same context and DO have the missing field populated.
            Use the most common or canonical value found among those siblings to fill in the gap.
      3. Update all rows where a normalized or propagated value was determined using update_rows, matching on row ID and updating only the affected columns.
         Skip rows where no new value could be determined.

    INSTRUCTIONS
  end
end
