require 'rails_helper'

RSpec.describe ToolCall, type: :model do
  it 'can be persisted' do
    tool_call = create(:tool_call)
    expect(tool_call).to be_persisted
  end

  it 'belongs to a message' do
    message   = create(:message)
    tool_call = create(:tool_call, message: message)
    expect(tool_call.message).to eq(message)
  end

  it 'stores a tool_call_id' do
    tool_call = create(:tool_call, tool_call_id: 'call_abc123')
    expect(tool_call.tool_call_id).to eq('call_abc123')
  end

  it 'stores the tool name' do
    tool_call = create(:tool_call, name: 'search_emails')
    expect(tool_call.name).to eq('search_emails')
  end
end
