# frozen_string_literal: true

require "capybara/rspec"
require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 900 ],
    process_timeout: ENV["CI"] ? 60 : 15,
    timeout: 10,
    headless: true,
    browser_options: ENV["CI"] ? { "no-sandbox" => nil, "disable-dev-shm-usage" => nil, "disable-gpu" => nil } : {},
    browser_path: ENV["CHROME_BIN"]
  )
end

Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5
Capybara.server = :webrick
Capybara.disable_animation = true
