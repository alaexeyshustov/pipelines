
require "rails_helper"

RSpec.describe "Home" do
  describe "GET /" do
    it "returns 200" do
      get root_path
      expect(response).to have_http_status(:ok)
    end
  end
end
