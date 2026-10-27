module Emails
  class CreateLabelTool < RubyLLM::Tool
    def self.readonly? = false

    description "Create a new label (Gmail) or folder (Yahoo) in the mail provider."

    parameter :provider, type: :string, description: 'Email provider: "gmail" or "yahoo"', required: true
    parameter :name,     type: :string, description: "Name of the label or folder to create",  required: true

    def name = "create_label"

    def execute(provider:, name:)
      Emails.create_label(provider, name: name)
    end
  end
end
