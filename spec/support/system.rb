# Rails 8.1 handles transactional fixture sharing between the test thread
# and the WEBrick server thread automatically — DatabaseCleaner is not needed.
RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :rack_test }
  # driven_by re-registers :cuprite, so driver options must be passed here.
  config.before(:each, :js, type: :system) do
    driven_by :cuprite, screen_size: [ 1400, 900 ], options: {
      process_timeout: ENV["CI"] ? 60 : 15,
      timeout: 10,
      headless: true,
      browser_options: ENV["CI"] ? { "no-sandbox" => nil, "disable-dev-shm-usage" => nil, "disable-gpu" => nil } : {}
    }
  end

  config.around(:each, type: :system) do |ex|
    old = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    ex.run
  ensure
    ActiveJob::Base.queue_adapter = old
  end
end
