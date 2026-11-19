# The whole app sits behind a login (GH #255). Request and system specs sign in by default
# through the real login endpoint or form; tag an example `:signed_out` to opt out.
# Loaded after spec/support/system.rb's hooks so the sign-in runs once `driven_by` has chosen the driver.
require_relative "../system"

module AuthenticationHelpers
  def signed_in_user
    @signed_in_user
  end

  # Signs in with a real POST to the login endpoint, so the session cookie is the one the app issues.
  # Forgery protection is switched off for the login itself: a spec that turns it on (to test CSRF) must still sign in.
  def sign_in(user = create(:user))
    protected_before = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    post session_path, params: { email_address: user.email_address, password: user.password }
    expect(cookies[:session_id]).to be_present
    user
  ensure
    ActionController::Base.allow_forgery_protection = protected_before
  end

  # `reset!` drops the login cookie along with the rest of the session; this logs the same user back in.
  def sign_in_again
    sign_in(signed_in_user) if signed_in_user
  end

  def sign_in_through_form(user = create(:user))
    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: user.password
    click_button "Sign in"
    expect(page).to have_css("[data-testid='sidebar']")
    user
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
  config.include AuthenticationHelpers, type: :system

  # The login rate limit counts in ActionController::Base.cache_store (a memory store in test).
  config.before(type: :request) do |example|
    ActionController::Base.cache_store.clear
    @signed_in_user = sign_in unless example.metadata[:signed_out]
  end

  config.before(type: :system) do |example|
    ActionController::Base.cache_store.clear
    @signed_in_user = sign_in_through_form unless example.metadata[:signed_out]
  end
end
