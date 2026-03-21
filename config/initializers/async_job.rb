Rails.application.config.async_job.define_queue("default") do
  dequeue Async::Job::Processor::Inline
end
