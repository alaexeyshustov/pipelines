module Documents
  class DuplicatesComponentPreview < ViewComponent::Preview
    def default
      document = Document.new(id: 1, title: "Lease.pdf")
      other = Document.new(id: 2, title: "Lease scan.pdf")
      duplicate = DocumentDuplicate.new(id: 1, document:, duplicate: other, similarity: 0.973)
      render(Documents::DuplicatesComponent.new(document:, duplicates: [ duplicate ]))
    end
  end
end
