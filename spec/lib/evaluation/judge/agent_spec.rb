
require "rails_helper"

RSpec.describe Evaluation::Judge::Agent do
  it "initializes without error (schema fields are valid for the ruby_llm-schema DSL)" do
    # Regression: `required:` inside an array block was passed to `string_schema`/`integer_schema`
    # which don't accept that keyword, raising ArgumentError silently swallowed by call_judge.
    expect { described_class.create }.not_to raise_error
  end
end
