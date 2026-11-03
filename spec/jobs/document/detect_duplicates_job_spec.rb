require "rails_helper"

RSpec.describe Document::DetectDuplicatesJob do
  include EmbeddingHelpers

  it "flags near-duplicates of the document" do
    document = create(:document)
    other = create(:document)
    embed_as(document, unit_vector(0))
    embed_as(other, unit_vector(0))

    described_class.perform_now(document.id)

    expect(DocumentDuplicate.sole).to have_attributes(document:, duplicate: other)
  end

  it "ignores a document deleted in the meantime" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
