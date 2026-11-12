module Emails
  class ClassifyTool < RubyLLM::Tool
    # The classifier agent is injected (see Orchestration::ToolResolver) so the
    # tools layer doesn't depend on the orchestration subsystem.
    class_attribute :classifier, instance_accessor: false

    def self.readonly? = true

    def self.with_classifier(classifier)
      Class.new(self) { self.classifier = classifier } # : singleton(ClassifyTool)
    end

    description "Classify a batch of emails and return tags for each one."

    parameter :emails,
          type: :array,
          description: "List of emails to classify. Each item must have 'id' and 'subject' fields."

    def name = "classify_emails"

    def execute(emails:, **_opts)
      return {} if emails.blank?

      emails = emails.filter_map do |email|
        email = JSON.parse(email) if email.is_a?(String)
        next unless email.is_a?(Hash)

        {
          "id" => email["id"],
          "subject" => email["subject"]
        }
      rescue JSON::ParserError
        nil
      end

      input = { emails: emails }.to_json
      classifier.create.ask(input).parsed
    end

    private

    def classifier
      self.class.classifier or raise NotImplementedError, "#{self.class} needs a classifier; use .with_classifier"
    end
  end
end
