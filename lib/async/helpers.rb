module Async
  module Helpers
    def self.with_semaphore(concurrency: 5, items: [])
      Sync do
        semaphore = Async::Semaphore.new(concurrency)
        tasks = items.map do |item|
          semaphore.async { yield(item) }
        end
        tasks.flat_map(&:wait)
      end
    end
  end
end
