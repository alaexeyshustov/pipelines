class ClassifyEmailsTool < RubyLLM::Tool
  description "Classify a batch of emails and return tags for each one."

  param :emails,
        type: :array,
        desc: "List of emails to classify. Each item must have 'id' and 'subject' fields."

  def execute(emails:, **_opts)
    return {} if emails.nil? || emails.empty?

    emails = emails.filter_map do |email|
      email = JSON.parse(email) if email.is_a?(String)
      next unless email.is_a?(Hash)

      {
        id: email["id"] || email[:id],
        subject: email["subject"] || email[:subject]
      }
    rescue JSON::ParserError
      nil
    end

    input = { emails: emails }.to_json
    EmailClassifyAgent.create.ask(input).content
  end

  private

  def reshape(content)
    results = content.is_a?(Hash) ? content["results"] || content[:results] : nil
    return {} unless results.is_a?(Array)

    results.each_with_object({}) do |entry, hash|
      id   = entry["id"]   || entry[:id]
      tags = entry["tags"] || entry[:tags]
      hash[id] = tags if id && tags
    end
  end
end
