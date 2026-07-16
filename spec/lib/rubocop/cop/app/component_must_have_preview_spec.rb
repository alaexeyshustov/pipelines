
require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::ComponentMustHavePreview, :config do
  let(:file) { "/project/app/components/ui/foo_component.rb" }
  let(:preview_path) { "/project/spec/components/previews/ui/foo_component_preview.rb" }

  context "when the preview file is missing" do
    before { allow(File).to receive(:exist?).with(preview_path).and_return(false) }

    it "registers an offense" do
      expect_offense(<<~RUBY, file)
        class FooComponent < ViewComponent::Base
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Missing preview file for this component: expected `#{preview_path}`.
        end
      RUBY
    end
  end

  context "when the preview file exists" do
    before { allow(File).to receive(:exist?).with(preview_path).and_return(true) }

    it "registers no offense" do
      expect_no_offenses(<<~RUBY, file)
        class FooComponent < ViewComponent::Base
        end
      RUBY
    end
  end

  it "registers no offense for non-component files" do
    expect_no_offenses(<<~RUBY, "/project/app/components/ui/table_row.rb")
      class TableRow; end
    RUBY
  end
end
