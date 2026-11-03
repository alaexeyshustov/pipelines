# Manual tag editing for Email and Document (nested under either). Writes +source: manual+ taggings.
class TaggingsController < ApplicationController
  before_action :set_taggable

  def create
    form = Tags::ManualTaggingForm.new(taggable: @taggable, **tagging_params.to_h.symbolize_keys)

    if form.save
      redirect_to @taggable, notice: "Tag was successfully added."
    else
      @form_errors = form.errors
      render_taggable_show
    end
  end

  def destroy
    @taggable.taggings.find(params[:id]).destroy!
    redirect_to @taggable, notice: "Tag was removed."
  end

  private

  def set_taggable
    @taggable = params[:email_id] ? Email.find(params[:email_id]) : Document.find(params[:document_id])
  end

  def tagging_params
    params.expect(tagging: [ :tag_id, :subtag_id ])
  end

  def render_taggable_show
    @taggings = @taggable.taggings.includes(:tag, :subtag).order(:id)
    @tags = Tag.includes(:subtags).order(:id)
    instance_variable_set(:"@#{@taggable.model_name.element}", @taggable)
    render "#{@taggable.model_name.plural}/show", status: :unprocessable_content
  end
end
