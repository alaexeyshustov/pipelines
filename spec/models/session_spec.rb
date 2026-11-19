require "rails_helper"

RSpec.describe Session do
  it "has a valid factory" do
    expect(build(:session)).to be_valid
  end

  it "belongs to a user" do
    user = create(:user)

    expect(create(:session, user:).user).to eq(user)
  end

  it "is invalid without a user" do
    expect(build(:session, user: nil)).not_to be_valid
  end

  it "records the client's ip address and user agent" do
    session = create(:session, ip_address: "10.0.0.7", user_agent: "Mozilla/5.0").reload

    expect(session).to have_attributes(ip_address: "10.0.0.7", user_agent: "Mozilla/5.0")
  end
end
