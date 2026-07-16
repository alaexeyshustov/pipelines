
# Rails 8.1 handles transactional fixture sharing between the test thread
# and the WEBrick server thread automatically — DatabaseCleaner is not needed.
RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :rack_test }
  config.before(:each, :js, type: :system) { driven_by :cuprite }

  config.around(:each, type: :system) do |ex|
    old = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    ex.run
  ensure
    ActiveJob::Base.queue_adapter = old
  end
end
