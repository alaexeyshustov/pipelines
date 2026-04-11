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
  
  def batch
    ids = params[:ids]
    batch_action = params[:batch_action]

    result = Chats::BatchService.new(ids: ids.to_a, batch_action: batch_action.to_s).call
    redirect_to chats_path, **flash_for(result)
  end
end
