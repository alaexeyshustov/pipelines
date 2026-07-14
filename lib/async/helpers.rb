module Async
  module Helpers
    def self.with_semaphore(limit)
      semaphore = Async::Semaphore.new(limit)
      tasks = yield(semaphore) # : Array[Async::Task[untyped]]
      tasks.flat_map(&:wait)
    end

    def self.with_barrier(limit)
      barrier = Async::Barrier.new
      semaphore = Async::Semaphore.new(limit, parent: barrier)
      yield(semaphore)
      barrier.wait
    end
  end
end
