# frozen_string_literal: true

# Shared example for Records::*Job specs.
# Requires `captured_inputs` to be defined as a let in the outer context (an Array
# populated by the stub agent's #ask method via stub_const).
# `empty_key` is the JSON key whose value should be empty when no records match the given IDs.
RSpec.shared_examples 'a records job that ignores missing IDs' do |empty_key|
  it 'ignores IDs not in the database' do
    described_class.perform_now([ 0 ])
    parsed = JSON.parse(captured_inputs.last)
    expect(parsed[empty_key]).to be_empty
  end
end
