require "rails_helper"

RSpec.describe Async::Helpers do
  describe ".with_semaphore" do
    it "calls the block once per item and flattens the results" do
      result = described_class.with_semaphore(concurrency: 2, items: [ 1, 2, 3 ]) { |n| [ n, n * 2 ] }

      expect(result).to contain_exactly(1, 2, 2, 4, 3, 6)
    end

    it "passes each item through to the block" do
      seen = []

      described_class.with_semaphore(concurrency: 2, items: [ 1, 2, 3 ]) { |n| seen << n }

      expect(seen).to contain_exactly(1, 2, 3)
    end

    it "returns an empty array when items is empty" do
      expect(described_class.with_semaphore(concurrency: 2, items: []) { |n| n }).to eq([])
    end

    it "defaults to a concurrency of 5 and an empty items list" do
      expect(described_class.with_semaphore { |n| n }).to eq([])
    end

    it "keeps non-array block results unflattened" do
      result = described_class.with_semaphore(concurrency: 2, items: [ 1, 2, 3 ]) { |n| n }

      expect(result).to contain_exactly(1, 2, 3)
    end
  end

  describe ".with_barrier" do
    it "calls the block once per item and waits for all of them to complete" do
      completed = []

      described_class.with_barrier(concurrency: 2, items: [ 1, 2, 3 ]) { |n| completed << n }

      expect(completed).to contain_exactly(1, 2, 3)
    end

    it "does not raise when items is empty" do
      expect { described_class.with_barrier(concurrency: 2, items: []) { |n| n } }.not_to raise_error
    end

    it "defaults to a concurrency of 5 and an empty items list" do
      expect { described_class.with_barrier { |n| n } }.not_to raise_error
    end
  end
end
