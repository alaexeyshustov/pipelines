# frozen_string_literal: true

require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::NoHtmlBuildingInHelper, :config do
  let(:file) { "app/helpers/foo_helper.rb" }

  it "registers an offense for content_tag" do
    expect_offense(<<~RUBY, file)
      module FooHelper
        def badge(text)
          content_tag(:span, text)
          ^^^^^^^^^^^^^^^^^^^^^^^^ Do not build HTML in helpers with `content_tag`; use a ViewComponent instead.
        end
      end
    RUBY
  end

  it "registers an offense for concat" do
    expect_offense(<<~RUBY, file)
      module FooHelper
        def items(list)
          concat("<ul>")
          ^^^^^^^^^^^^^^ Do not build HTML in helpers with `concat`; use a ViewComponent instead.
        end
      end
    RUBY
  end

  it "registers an offense for tag. builder calls" do
    expect_offense(<<~RUBY, file)
      module FooHelper
        def badge(text)
          tag.span(text, class: "badge")
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not build HTML in helpers with `tag.span`; use a ViewComponent instead.
        end
      end
    RUBY
  end

  it "registers no offense for plain string helpers" do
    expect_no_offenses(<<~RUBY, file)
      module FooHelper
        def badge_class(status)
          status == "active" ? "green" : "gray"
        end
      end
    RUBY
  end

  it "registers no offense outside helper files" do
    expect_no_offenses(<<~RUBY, "app/components/ui/foo_component.rb")
      class FooComponent < ViewComponent::Base
        def call
          content_tag(:div, "hello")
        end
      end
    RUBY
  end
end
