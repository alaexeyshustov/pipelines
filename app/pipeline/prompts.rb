module Pipeline
  # Builds the prompt strings passed to each workflow agent.
  class Prompts
    def build_init_message
      "Read the 'application_mails' table using manage_database (action: 'read', table: 'application_mails'). " \
      "Return ONLY a valid JSON object: " \
      '{"latest_date": "YYYY-MM-DD or no_date", "existing_ids": ["id1", ...]}'
    end

    def build_fetch_message(provider, after_date, before_date = nil)
      msg = "List all emails from provider \"#{provider}\" with after_date \"#{after_date}\""
      msg += " and before_date \"#{before_date}\"" if before_date
      msg += ". Paginate if needed (offset by 100 until fewer than 100 returned). " \
             "Return ONLY a valid JSON array: " \
             '[{"id":"...","subject":"...","date":"...","from":"..."}]'
      msg
    end

    def build_label_store_message(batch)
      "Process these job emails. Label each in its provider, then insert all rows " \
      "into the 'application_mails' table using manage_database (action: 'add_rows'):\n#{batch.to_json}"
    end

    def build_reconcile_message(added_rows)
      "New application_mails rows:\n#{added_rows.to_json}\n\n" \
      "Update the 'interviews' table using manage_database. " \
      "Read it first (action: 'read', table: 'interviews') to see existing data, " \
      "then add new entries (add_rows) or update existing ones (update_rows)."
    end
  end
end
