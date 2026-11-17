require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::NoUpdateInBefore, :config do
  let(:file) { "spec/lib/foo_spec.rb" }

  it "registers an offense for update! in a before block" do
    expect_offense(<<~RUBY, file)
      before do
        pipeline.update!(model: "x")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Create records in their final state instead of updating them in `before`.
      end
    RUBY
  end

  it "registers an offense for update in a brace before block" do
    expect_offense(<<~RUBY, file)
      before { agent.update(prompt: nil) }
               ^^^^^^^^^^^^^^^^^^^^^^^^^ Create records in their final state instead of updating them in `before`.
    RUBY
  end

  it "registers no offense in examples, let blocks or outside specs" do
    expect_no_offenses(<<~RUBY, file)
      let(:agent) { create(:agent).tap { |a| a.save! } }

      it "updates" do
        agent.update!(prompt: nil)
      end
    RUBY
    expect_no_offenses(<<~RUBY, "app/models/foo.rb")
      before { record.update!(x: 1) }
    RUBY
  end
end
