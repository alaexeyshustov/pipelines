class SearchesController < ApplicationController
  def show
    @query = params[:q].to_s.strip
    return if @query.empty?

    @email_hits = Email::SearchQuery.call(@query).hits
    @document_hits = Document::SearchQuery.call(@query).hits
  end
end
