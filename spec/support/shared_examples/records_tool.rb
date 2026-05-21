# frozen_string_literal: true

RSpec.shared_examples 'a records tool that handles unknown tables' do
  it 'returns an error for an unknown table' do
    result = tool.execute(table: 'unknown')
    expect(result[:error]).to match(/Unknown table/)
  end
end
