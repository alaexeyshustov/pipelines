# frozen_string_literal: true

class GetLabelsTool < RubyLLM::Tool
  description "List all available labels for a mail provider. " \
              "Gmail returns label IDs and names. Yahoo returns folder names."

  param :provider, type: :string, desc: 'Email provider: "gmail" or "yahoo"', required: true

  def execute(provider:)
    Emails.get_labels(provider)
  end
end
