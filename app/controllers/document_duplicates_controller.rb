# Review of the near-duplicate candidates of a Document (GH #227): confirm or dismiss a pair.
class DocumentDuplicatesController < ApplicationController
  before_action :set_duplicate

  def confirm
    @duplicate.confirmed!
    redirect_to document_path(@document), notice: "Marked as duplicate."
  end

  def dismiss
    @duplicate.dismissed!
    redirect_to document_path(@document), notice: "Duplicate candidate dismissed."
  end

  private

  def set_duplicate
    @document = Document.find(params[:document_id])
    @duplicate = DocumentDuplicate.involving(@document).find(params[:id])
  end
end
