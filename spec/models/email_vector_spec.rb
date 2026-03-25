require 'rails_helper'

RSpec.describe EmailVector, type: :model do
  let(:embedding) { Array.new(1536, 0.1) }
  let(:serialized) { embedding.pack("f*") }

  describe '.upsert_embedding' do
    it 'executes an INSERT OR REPLACE with serialized embedding' do
      expect(described_class.connection).to receive(:execute).with(
        "INSERT OR REPLACE INTO email_vectors(email_id, embedding) VALUES (?, ?)",
        [ 'email_123', serialized ]
      )

      described_class.upsert_embedding(email_id: 'email_123', embedding: embedding)
    end
  end

  describe '.search' do
    it 'queries the vec0 table and returns email_id/distance hashes' do
      raw_rows = [ [ 'email_1', 0.12 ], [ 'email_2', 0.34 ] ]
      allow(described_class.connection).to receive(:execute).with(
        "SELECT email_id, distance FROM email_vectors WHERE embedding MATCH ? ORDER BY distance LIMIT ?",
        [ serialized, 5 ]
      ).and_return(raw_rows)

      results = described_class.search(embedding)
      expect(results).to eq([
        { email_id: 'email_1', distance: 0.12 },
        { email_id: 'email_2', distance: 0.34 }
      ])
    end

    it 'respects a custom limit' do
      allow(described_class.connection).to receive(:execute).with(
        "SELECT email_id, distance FROM email_vectors WHERE embedding MATCH ? ORDER BY distance LIMIT ?",
        [ serialized, 10 ]
      ).and_return([])

      described_class.search(embedding, limit: 10)
    end

    it 'returns an empty array when there are no matches' do
      allow(described_class.connection).to receive(:execute).with(anything, anything).and_return([])

      expect(described_class.search(embedding)).to eq([])
    end
  end
end
