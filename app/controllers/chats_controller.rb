# frozen_string_literal: true

class ChatsController < ApplicationController
  def index
    @pagy, @chats = pagy(:offset, Chat.includes(:model).order(created_at: :desc))
  end

  def show
    @chat = Chat.includes(messages: :tool_calls).find(params[:id])
  end

  def destroy
    Chat.find(params[:id]).destroy
    redirect_to chats_path, status: :see_other
  end
end
