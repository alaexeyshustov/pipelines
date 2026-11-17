require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::NoSideEffectAasmCallbacks, :config do
  let(:file) { "app/models/experiment.rb" }

  it "registers an offense for an LLM call inside an aasm block" do
    expect_offense(<<~RUBY, file)
      aasm column: :status do
        event :complete, after: -> { RubyLLM.chat.ask("done") } do
                                     ^^^^^^^ Do not trigger jobs, mail or LLM calls from AASM; the service or job that fires the event does that.
          transitions from: :running, to: :completed
        end
      end
    RUBY
  end

  it "registers an offense for enqueueing a job inside an aasm block" do
    expect_offense(<<~RUBY, file)
      aasm column: :status do
        state :done, after_enter: -> { NotifyJob.perform_later(id) }
                                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not trigger jobs, mail or LLM calls from AASM; the service or job that fires the event does that.
      end
    RUBY
  end

  it "registers no offense for data-only callbacks or outside aasm" do
    expect_no_offenses(<<~RUBY, file)
      aasm column: :status do
        event :start, after: -> { touch(:started_at) } do
          transitions from: :pending, to: :running
        end
      end

      NotifyJob.perform_later(id)
    RUBY
  end
end
