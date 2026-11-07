class EmailsController < ApplicationController
  def show
    @email = Email.find(params[:id])
    @taggings = @email.taggings.includes(:tag, :subtag).order(:id)
    @tags = Tag.includes(:subtags).order(:id)
  end
end
