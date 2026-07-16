
module RecordsAgentHelpers
  OPENAI_COMPLETIONS_URL  = 'https://api.openai.com/v1/chat/completions'
  MISTRAL_COMPLETIONS_URL = 'https://api.mistral.ai/v1/chat/completions'

  def openai_completions_url  = OPENAI_COMPLETIONS_URL
  def mistral_completions_url = MISTRAL_COMPLETIONS_URL

  def stub_openai_agent_response(content:)
    stub_request(:post, openai_completions_url)
      .to_return(
        status: 200,
        body: {
          id: 'cmpl-test', object: 'chat.completion', model: 'gpt-5.1',
          choices: [ { index: 0, message: { role: 'assistant', content: content }, finish_reason: 'stop' } ],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_mistral_agent_response(content:)
    stub_request(:post, mistral_completions_url)
      .to_return(
        status: 200,
        body: {
          id: 'cmpl-test', object: 'chat.completion', model: 'mistral-large-latest',
          choices: [ { index: 0, message: { role: 'assistant', content: content }, finish_reason: 'stop' } ],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end
end
