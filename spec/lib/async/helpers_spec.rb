require "rails_helper"

RSpec.describe Async::Helpers do
  describe ".with_semaphore" do
    it "yields a semaphore configured with the given limit" do
      Sync do
        described_class.with_semaphore(3) do |semaphore|
          expect(semaphore).to be_a(Async::Semaphore)
          []
        end
      end
    end

    it "waits for and flattens the results of the dispatched tasks" do
      result = Sync do
        described_class.with_semaphore(2) do |semaphore|
          [ 1, 2, 3 ].map { |n| semaphore.async { [ n, n * 2 ] } }
        end
      end

      expect(result).to contain_exactly(1, 2, 2, 4, 3, 6)
    end

    it "returns an empty array when no tasks are dispatched" do
      result = Sync do
        described_class.with_semaphore(2) { |_semaphore| [] }
      end

      expect(result).to eq([])
    end
  end

  describe ".with_barrier" do
    it "yields a semaphore backed by a barrier and waits for all dispatched tasks" do
      completed = []

      Sync do
        described_class.with_barrier(2) do |semaphore|
          [ 1, 2, 3 ].each { |n| semaphore.async { completed << n } }
        end
      end

      expect(completed).to contain_exactly(1, 2, 3)
    end
  end
end
