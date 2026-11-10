class DocumentsController < ApplicationController
  def index
    if params[:q].present?
      @hits = Document::SearchQuery.call(params[:q])
    else
      @pagy, documents = pagy(:offset, Document.order(created_at: :desc))
      @hits = documents.map { |document| Document::SearchQuery::Hit.new(document:, rank: nil, snippet: nil) }
    end
  end

  def show
    @document = Document.find(params[:id])
    @taggings = @document.taggings.includes(:tag, :subtag).order(:id)
    @tags = Tag.includes(:subtags).order(:id)
    @duplicates = DocumentDuplicate.candidates_for(@document)
  end

  def download
    document = Document.find(params[:id]) # a missing record is a 404, not a failed download
    send_original(document)
  end

  private

  def send_original(document)
    file = Document::Download.call(document)
    send_data file.data, filename: file.filename, type: file.mime_type, disposition: "attachment"
  rescue StandardError => error
    Rails.logger.error("[DocumentsController] download of document #{document.id} failed: #{error.class}: #{error.message}")
    redirect_to document_path(document), alert: "Could not fetch the original file."
  end
end
