class TagsController < ApplicationController
  def index
    @tags = Tag.includes(:subtags).order(:id)
    @form_errors = {}
  end
end
