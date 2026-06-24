# frozen_string_literal: true

require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::AasmMustSpecifyColumn, :config do
  let(:file) { "app/models/order.rb" }

  it "registers an offense when aasm block has no column:" do
    expect_offense(<<~RUBY, file)
      class Order
        aasm do
        ^^^^ Specify the `column:` keyword in `aasm` blocks (e.g., `aasm column: :status do`).
          state :pending
        end
      end
    RUBY
  end

  it "registers no offense when column: is specified" do
    expect_no_offenses(<<~RUBY, file)
      class Order
        aasm column: :status do
          state :pending
        end
      end
    RUBY
  end

  it "registers no offense outside model files" do
    expect_no_offenses(<<~RUBY, "app/services/foo_service.rb")
      class Foo
        aasm do
          state :pending
        end
      end
    RUBY
  end
end
