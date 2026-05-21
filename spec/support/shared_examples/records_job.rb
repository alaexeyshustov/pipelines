# frozen_string_literal: true

# Shared example for Records::*Job specs.
# Requires `agent` to be defined as a let/subject in the outer context (an instance_double of the agent class).
# `empty_key` is the JSON key whose value should be empty when no records match the given IDs.
RSpec.shared_examples 'a records job that ignores missing IDs' do |empty_key|
  it 'ignores IDs not in the database' do
    described_class.perform_now([ 0 ])

    expect(agent).to have_received(:ask) do |input|
      parsed = JSON.parse(input)
      expect(parsed[empty_key]).to be_empty
    end
  end
end
