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
  end

  def download
    document = Document.find(params[:id])
    file = Document::Download.call(document)
    send_data file.data, filename: file.filename, type: file.mime_type, disposition: "attachment"
  rescue StandardError => error
    redirect_to document_path(document), alert: "Could not fetch the original: #{error.message}"
  end
end
