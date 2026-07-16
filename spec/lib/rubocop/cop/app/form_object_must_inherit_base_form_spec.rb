
require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::FormObjectMustInheritBaseForm, :config do
  let(:file) { "app/forms/foo_form.rb" }

  it "registers an offense when not inheriting from BaseForm" do
    expect_offense(<<~RUBY, file)
      class FooForm
      ^^^^^^^^^^^^^ Form objects must inherit from `::BaseForm`.
      end
    RUBY
  end

  it "registers no offense when inheriting from ::BaseForm" do
    expect_no_offenses(<<~RUBY, file)
      class FooForm < ::BaseForm
      end
    RUBY
  end

  it "registers no offense when inheriting from BaseForm (without leading ::)" do
    expect_no_offenses(<<~RUBY, file)
      class FooForm < BaseForm
      end
    RUBY
  end

  it "registers no offense for BaseForm itself" do
    expect_no_offenses(<<~RUBY, file)
      class BaseForm
        include ActiveModel::Validations
        include ActiveModel::Attributes
      end
    RUBY
  end

  it "registers no offense outside form files" do
    expect_no_offenses(<<~RUBY, "app/models/foo.rb")
      class Foo; end
    RUBY
  end
end
