require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::NoQueriesInComponent, :config do
  let(:file) { "app/components/foo_component.rb" }

  it "registers an offense for a query on a model constant" do
    expect_offense(<<~RUBY, file)
      Metric.for_agent(@name).order(:name)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not query ActiveRecord in a component; have the caller pass loaded data.
    RUBY
  end

  it "registers an offense for a query on an association" do
    expect_offense(<<~RUBY, file)
      @experiment.samples.count
      ^^^^^^^^^^^^^^^^^^^^^^^^^ Do not query ActiveRecord in a component; have the caller pass loaded data.
    RUBY
  end

  it "registers no offense for enumerable calls on passed-in collections" do
    expect_no_offenses(<<~RUBY, file)
      @validator_results.find { |r| r.id == @id }
      @rows.count
      @tools.group_by { |t| t.split("::").first }
      @schema["enum"]&.first
    RUBY
  end

  it "registers no offense for a block-filtered count" do
    expect_no_offenses(<<~RUBY, file)
      @run.steps.count { |s| s.failed? }
    RUBY
  end

  it "registers no offense in previews or outside components" do
    expect_no_offenses(<<~RUBY, "spec/components/previews/foo_component_preview.rb")
      Metric.where(name: "x")
    RUBY
    expect_no_offenses(<<~RUBY, "app/controllers/foo_controller.rb")
      Metric.where(name: "x")
    RUBY
  end
end
