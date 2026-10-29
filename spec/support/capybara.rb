require "capybara/rspec"
require "capybara/cuprite"

Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5
Capybara.server = :webrick
Capybara.disable_animation = true
