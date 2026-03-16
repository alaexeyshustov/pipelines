module Tools
  class ClassifyEmailsTool < RubyLLM::Tool
    description "Classify a list of emails by their subject lines and return suggested tags. " \
                "Accepts an array of {id, title} objects and returns a mapping of id to tags array."

    param :emails, type: :array, desc: 'Array of email objects, each with "id" and "title" (subject line). ' \
                                       'Example: [{"id": "abc123", "title": "Your order has shipped"}]', required: true

    class << self
      attr_accessor :classifier
    end

    def execute(emails:)
      self.class.classifier.classify(emails)
    end
  end
end
