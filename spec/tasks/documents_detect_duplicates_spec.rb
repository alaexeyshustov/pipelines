require "rails_helper"
require "rake"

RSpec.describe "documents:detect_duplicates" do # rubocop:disable RSpec/DescribeClass
  include EmbeddingHelpers
  include RakeTaskHelpers

  before { load_rake_task("documents:detect_duplicates") }

  it "scans every embedded document and reports the flagged pairs" do
    first = create(:document)
    second = create(:document)
    third = create(:document)
    embed_as(first, unit_vector(0))
    embed_as(second, unit_vector(0))
    embed_as(third, unit_vector(5))

    expect { Rake::Task["documents:detect_duplicates"].invoke }.to output(/1 duplicate pair/).to_stdout

    expect(DocumentDuplicate.includes(:document, :duplicate).sole).to have_attributes(document: first, duplicate: second)
  end
end
