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
end
