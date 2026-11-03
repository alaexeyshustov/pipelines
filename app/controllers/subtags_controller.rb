class SubtagsController < ApplicationController
  def create
    tag = Tag.find(params[:tag_id])
    form = Tags::SubtagForm.new(tag:, **subtag_params.to_h.symbolize_keys)

    if form.save
      redirect_to tags_path, notice: "Subtag was successfully added."
    else
      @tags = Tag.includes(:subtags).order(:id)
      @form_errors = { tag.id => form.errors }
      render "tags/index", status: :unprocessable_content
    end
  end

  private

  def subtag_params
    params.expect(subtag: [ :name ])
  end
end
