require "rails_helper"

RSpec.describe Evaluation::UsageScope do
  let(:experiment) { create(:evaluation_experiment) }

  def stub_openai
    stub_request(:post, %r{api\.openai\.com}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: "c", object: "chat.completion", model: "gpt-5.4",
              choices: [ { index: 0, message: { role: "assistant", content: "hi" }, finish_reason: "stop" } ],
              usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } }.to_json
    )
  end

  it "returns the block value and restores the previous owner" do
    expect(described_class.call(experiment) { :value }).to eq(:value)
    expect(RubyLLM::Accounting::Usage.owner).to be_nil
  end

  it "owns usage rows of acts_as_chat chats" do
    stub_openai
    chat = Chat.create!(model: "gpt-5.4")
    described_class.call(experiment) { chat.ask("hello") }

    expect(RubyLLM::ActiveRecord::Usage.where(owner: experiment).pluck(:input_tokens, :output_tokens)).to eq([ [ 10, 5 ] ])
  end

  it "owns usage rows of plain chats" do
    stub_openai
    described_class.call(experiment) { RubyLLM.chat(model: "gpt-5.4").ask("hello") }

    expect(RubyLLM::ActiveRecord::Usage.where(owner: experiment).count).to eq(1)
  end

  it "applies inside an ActiveJob run by the test adapter (owner set in #perform)" do
    request_stub = stub_openai
    stub_const("UsageScopeProbeJob", Class.new(ApplicationJob) do
      def perform(experiment_id)
        Evaluation::UsageScope.call(Evaluation::Experiment.find(experiment_id)) { Chat.create!(model: "gpt-5.4").ask("hello") }
      end
    end)

    UsageScopeProbeJob.perform_now(experiment.id)

    expect(request_stub).to have_been_requested
    expect(RubyLLM::ActiveRecord::Usage.where(owner: experiment).count).to eq(1)
  end
end
