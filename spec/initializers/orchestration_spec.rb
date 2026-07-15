require "rails_helper"

RSpec.describe "Orchestration initializer" do # rubocop:disable RSpec/DescribeClass
  it "wires Orchestration.prompt_resolver to Evaluation::ActivePromptResolver at boot" do
    expect(Orchestration.prompt_resolver).to eq(Evaluation::ActivePromptResolver)
  end
end
