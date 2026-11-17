require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::NoAnonymousClassInSpec, :config do
  let(:file) { "spec/lib/foo_spec.rb" }

  it "registers an offense for an inline anonymous class" do
    expect_offense(<<~RUBY, file)
      let(:tool) { Class.new(RubyLLM::Tool) }
                   ^^^^^^^^^^^^^^^^^^^^^^^^ Name anonymous classes with `stub_const("Name", Class.new)`.
    RUBY
  end

  it "registers no offense inside stub_const" do
    expect_no_offenses(<<~RUBY, file)
      before do
        stub_const("FakeTool", Class.new(RubyLLM::Tool) do
          "fake"
        end)
        stub_const("OtherTool", Class.new)
      end
    RUBY
  end

  it "registers no offense outside specs" do
    expect_no_offenses(<<~RUBY, "app/models/foo.rb")
      Error = Class.new(StandardError)
    RUBY
  end
end
