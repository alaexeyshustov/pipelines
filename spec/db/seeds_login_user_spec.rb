require "rails_helper"
require "rake"

RSpec.describe "Seeds: login user" do # rubocop:disable RSpec/DescribeClass
  include RakeTaskHelpers

  around do |example|
    saved = ENV.values_at("ADMIN_EMAIL", "ADMIN_PASSWORD")
    example.run
  ensure
    ENV["ADMIN_EMAIL"], ENV["ADMIN_PASSWORD"] = saved
  end

  # Seeding is per-record by design; the examples check what it left behind.
  def seed
    load_rake_task("users:upsert")
    Prosopite.pause { load Rails.root.join("db/seeds.rb") }
  end

  it "creates the login user when ADMIN_EMAIL is set" do
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_PASSWORD"] = "s3cret-passw0rd"

    expect { seed }.to change(User, :count).by(1)

    expect(User.authenticate_by(email_address: "admin@example.com", password: "s3cret-passw0rd")).to be_present
  end

  it "creates no user when ADMIN_EMAIL is unset" do
    ENV.delete("ADMIN_EMAIL")

    expect { seed }.not_to change(User, :count)
  end

  it "creates no user when ADMIN_EMAIL is blank" do
    ENV["ADMIN_EMAIL"] = ""

    expect { seed }.not_to change(User, :count)
  end
end
