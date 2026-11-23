require "rails_helper"

RSpec.describe "Signing in and out" do
  describe "from a signed out browser", :signed_out do
    let(:user) { create(:user, email_address: "admin@example.com", password: "s3cret-passw0rd") }

    def fill_in_credentials(password: user.password)
      fill_in "email_address", with: user.email_address
      fill_in "password", with: password
      click_button "Sign in"
    end

    it "sends a visitor to the login page" do
      visit root_path

      expect(page).to have_current_path(new_session_path)
      expect(page).to have_button("Sign in")
      expect(page).to have_no_css("[data-testid='sidebar']")
    end

    it "signs in, shows the dashboard with the sidebar, and signs out again", :aggregate_failures do
      visit new_session_path
      fill_in_credentials

      expect(page).to have_current_path(root_path)
      expect(page).to have_css("[data-testid='sidebar']", text: "admin@example.com")

      click_button "Sign out"

      expect(page).to have_current_path(new_session_path)
      expect(page).to have_button("Sign in")
    end

    it "returns to the page that was asked for" do
      visit interviews_path
      fill_in_credentials

      expect(page).to have_current_path(interviews_path)
    end

    it "stays on the login page with an error for a wrong password" do
      visit new_session_path
      fill_in_credentials(password: "wrong")

      expect(page).to have_current_path(new_session_path)
      expect(page).to have_no_css("[data-testid='sidebar']")
      expect(page).to have_css("[role='alert'], .bg-red-50")
    end
  end

  # The default sign-in in spec/support/helpers/authentication_helpers.rb, once per driver.
  describe "by default in system specs" do
    it "is signed in under rack_test" do
      visit root_path

      expect(page).to have_button("Sign out")
    end

    it "is signed in under Cuprite", :js do
      visit root_path

      expect(page).to have_button("Sign out")
    end
  end
end
