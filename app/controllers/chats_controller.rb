# frozen_string_literal: true

class ChatsController < ApplicationController
  def index
    collection = Chat.includes(:model).order(created_at: :desc)
    page  = [ params[:page].to_i, 1 ].max
    count = collection.count
    @pagy = Pagy::Offset.new(page: page, count: count)
    @chats = @pagy.records(collection)
  end

  def show
    @chat = Chat.includes(messages: :tool_calls).find(params[:id])
  end

  def destroy
    Chat.find(params[:id]).destroy
    redirect_to chats_path, status: :see_other
  end
end
