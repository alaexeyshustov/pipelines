# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Chats", type: :request do
  describe "GET /chats" do
    it "returns 200 with empty state" do
      get chats_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No chats found")
    end

    it "lists existing chats" do
      chat = create(:chat)
      get chats_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("##{chat.id}")
    end

    it "renders pagination when there are more chats than the page limit" do
      create_list(:chat, 21)
      get chats_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('aria-label="Pages"')
      expect(response.body).to include('aria-label="Next"')
    end

    it "does not render pagination when all chats fit on one page" do
      create_list(:chat, 3)
      get chats_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('aria-label="Pages"')
    end

    it "shows the requested page" do
      create_list(:chat, 21)
      get chats_path, params: { page: 2 }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('aria-label="Previous"')
    end
  end

  describe "GET /chats/:id" do
    it "returns 200 and shows the chat" do
      chat = create(:chat)
      get chat_path(chat)
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for a missing chat" do
      get chat_path(0)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /chats/:id" do
    it "destroys the chat and redirects to index" do
      chat = create(:chat)
      expect {
        delete chat_path(chat)
      }.to change(Chat, :count).by(-1)
      expect(response).to redirect_to(chats_path)
    end
  end
end
