# frozen_string_literal: true

class CreateLabelTool < RubyLLM::Tool
  description "Create a new label (Gmail) or folder (Yahoo) in the mail provider."

  param :provider, type: :string, desc: 'Email provider: "gmail" or "yahoo"', required: true
  param :name,     type: :string, desc: "Name of the label or folder to create",  required: true

  def execute(provider:, name:)
    Emails.create_label(provider, name: name)
  end
end
