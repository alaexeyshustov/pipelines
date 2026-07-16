
class SeedAgentsFromAppAgentsDir < ActiveRecord::Migration[8.1]
  # One entry per file under app/agents/.
  # Keep in sync with:
  #   - db/seeds.rb (AGENT_DEFINITIONS) for fresh installs
  #   - 20260504140000_backfill_agent_configs_from_legacy_classes.rb for existing installs
  AGENTS = [
    {
      name:   "Emails::ClassifyAgent",
      model:  "mistral-large-latest",
      tools:  %w[Records::TempFileTool],
      prompt: <<~PROMPT
        You are an email classifier. Your job is to tag a list of emails by their subject lines and return suggested tags.

        Input:
        {
          "emails": [
            {"id": "id of email", "subject": "Email subject line"}
          ]
        }

        Steps:
        1. For each email, analyze the subject line and suggest short lowercase classification tags that are relevant to the content of the email.
          Tags should be concise and descriptive (e.g. "job", "application", "interview", "offer").
      PROMPT
    },
    {
      name:   "Emails::FilterAgent",
      model:  "mistral-large-latest",
      tools:  %w[Records::TempFileTool],
      prompt: <<~PROMPT
        You are an email filtering expert. Your job is to identify <emails> from a list related to a <topic>.

        Input:
        {
          "topic": "The topic to filter by (e.g. 'job applications')",
          "emails": [
            {"id": "id of email", "subject": "Email subject line", "tags": ["list", "of", "classification", "tags"] }
          ]
        }

        Steps:
        3. Return ONLY emails tagged with ANY of tags related to the <topic>
          (e.g. for "job applications" topic, tags might include "job", "application", "interview", "offer", etc.).

        If no emails related to the <topic> are found, return an empty JSON array: []
      PROMPT
    },
    {
      name:   "Emails::MappingAgent",
      model:  "mistral-large-latest",
      tools:  %w[Emails::GetTool Records::TempFileTool],
      prompt: <<~PROMPT
        Your task is to map raw email data to a structured format for database insertion.

        Input:
        {
          "emails": ["list", "of", "emails", "to", "process"],
        }

        Steps:
        1. For each email in <emails>, call get_email to fetch its full content — this is mandatory before mapping any field.
        2. After reading the full email content, extract and map all required fields.
        3. Base the "action" field strictly on the email body text, not just the subject line.
      PROMPT
    },
    {
      name:   "Records::FillAgent",
      model:  "gpt-5.1",
      tools:  %w[Records::UpdateRowsTool Emails::GetTool],
      prompt: <<~PROMPT
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
      PROMPT
    },
    {
      name:   "Records::NormalizeAgent",
      model:  "gpt-5.1",
      tools:  %w[Records::ListRowsTool Records::ReadRowsTool Records::UpdateRowsTool Records::ReadSchemaTool Records::SearchSimilarTool],
      prompt: <<~PROMPT
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
      PROMPT
    },
    {
      name:   "Records::ReconcileAgent",
      model:  "gpt-5.1",
      tools:  %w[Records::ReadSchemaTool Records::TempFileTool Records::SearchSimilarTool Records::InsertRowsTool Records::UpdateRowsTool Records::ReadRowsTool],
      prompt: <<~PROMPT
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
      PROMPT
    },
    {
      name:   "Records::StoreAgent",
      model:  "mistral-large-latest",
      tools:  %w[Emails::GetLabelsTool Emails::CreateLabelTool Emails::AddLabelsTool Records::InsertRowsTool Records::ReadSchemaTool Emails::GetTool],
      prompt: <<~PROMPT
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
           If add_labels fails, skip labeling but continue processing.

        3. Store a new row in the <table> with the mapped data using insert_rows.
      PROMPT
    }
  ].freeze

  def up
    now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S.%6N")
    AGENTS.each do |agent|
      execute(<<~SQL)
        INSERT OR IGNORE INTO orchestration_agents
          (name, model, tools, prompt, enabled, created_at, updated_at)
        VALUES (
          #{quote(agent[:name])},
          #{quote(agent[:model])},
          #{quote(agent[:tools].to_json)},
          #{quote(agent[:prompt])},
          1,
          #{quote(now)},
          #{quote(now)}
        )
      SQL
    end
  end

  def down
    names = AGENTS.map { |a| quote(a[:name]) }.join(", ")
    execute("DELETE FROM orchestration_agents WHERE name IN (#{names})")
  end
end
