require 'rails_helper'

RSpec.describe Emails::Adapters::FixtureAdapter do
  let(:gmail_mailbox) do
    {
      'account' => 'me@gmail.test', 'history_id' => '100',
      'messages' => [
        { 'id' => 'g1', 'from' => 'a@x.test', 'to' => 'me@gmail.test', 'subject' => 'First',
          'date' => '2026-11-02T09:00:00Z', 'body' => 'one', 'html_body' => nil,
          'attachments' => [
            { 'id' => 'a1', 'filename' => 'cv.txt', 'mime_type' => 'text/plain', 'data' => 'hello!' },
            { 'id' => 'a2', 'filename' => 'b.txt', 'mime_type' => 'text/plain', 'data' => 'bb' }
          ] },
        { 'id' => 'g2', 'from' => 'b@x.test', 'to' => 'me@gmail.test', 'subject' => 'Second',
          'date' => '2026-11-04T09:00:00+02:00', 'body' => 'two', 'html_body' => '<p>two</p>',
          'attachments' => [ { 'id' => 'a3', 'filename' => 'u.txt', 'mime_type' => 'text/plain', 'data' => "caf\u00e9" } ] },
        { 'id' => 'g3', 'from' => 'c@x.test', 'to' => 'me@gmail.test', 'subject' => 'Third',
          'date' => '2026-11-06T09:00:00Z', 'body' => 'three' }
      ]
    }
  end
  let(:yahoo_mailbox) do
    {
      'account' => 'me@yahoo.test', 'uid_validity' => 7,
      'messages' => [
        { 'uid' => 1, 'from' => 'a@y.test', 'to' => 'me@yahoo.test', 'subject' => 'Y1',
          'date' => '2026-11-02T09:00:00Z', 'body' => 'one' },
        { 'uid' => 5, 'from' => 'a@y.test', 'to' => 'me@yahoo.test', 'subject' => 'Y5',
          'date' => '2026-11-06T09:00:00Z', 'body' => 'five' },
        { 'uid' => 3, 'from' => 'a@y.test', 'to' => 'me@yahoo.test', 'subject' => 'Y3',
          'date' => '2026-11-04T09:00:00Z', 'body' => 'three' }
      ]
    }
  end
  let(:gmail) { described_class.new(provider: 'gmail', mailbox: gmail_mailbox) }
  let(:yahoo) { described_class.new(provider: 'yahoo', mailbox: yahoo_mailbox) }
  let(:empty) { described_class.new(provider: 'gmail', mailbox: { 'account' => 'e@x.test', 'messages' => [] }) }

  describe '.from_env' do
    it 'builds the provider adapter from the JSON file' do
      path = Rails.root.join('tmp', "fixture_adapter_#{SecureRandom.hex(4)}.json")
      File.write(path, JSON.generate('gmail' => gmail_mailbox, 'yahoo' => yahoo_mailbox))

      adapter = described_class.from_env(provider: :yahoo, path: path)

      expect(adapter.account).to eq('me@yahoo.test')
      expect(adapter.inbox_status.uid_validity).to eq(7)
    ensure
      FileUtils.rm_f(path)
    end

    it 'requires the provider and path options' do
      expect { described_class.from_env }.to raise_error(KeyError)
    end

    it 'raises when the provider is missing from the file' do
      path = Rails.root.join('tmp', "fixture_adapter_#{SecureRandom.hex(4)}.json")
      File.write(path, JSON.generate('gmail' => gmail_mailbox))

      expect { described_class.from_env(provider: 'yahoo', path: path.to_s) }.to raise_error(KeyError)
    ensure
      FileUtils.rm_f(path)
    end
  end

  describe '#profile' do
    it 'returns the account and configured history id' do
      expect(gmail.profile).to eq(email_address: 'me@gmail.test', history_id: '100')
    end

    it 'defaults the history id to "1"' do
      expect(yahoo.profile).to eq(email_address: 'me@yahoo.test', history_id: '1')
    end
  end

  describe 'numeric fixture values' do
    let(:numeric) do
      described_class.new(provider: 'gmail', mailbox: {
        'account' => 42, 'messages' => [
          { 'id' => 7, 'from' => 1, 'to' => 2, 'subject' => 3, 'date' => '2026-11-02T09:00:00Z', 'body' => 4 }
        ]
      })
    end

    it 'coerces the account to a string' do
      expect(numeric.account).to eq('42')
    end

    it 'coerces a numeric history id to a string' do
      mailbox = { 'account' => 'a', 'history_id' => 123, 'uid_validity' => '9', 'messages' => [] }
      adapter = described_class.new(provider: 'gmail', mailbox:)

      expect(adapter.profile[:history_id]).to eq('123')
      expect(adapter.inbox_status.uid_validity).to eq(9)
    end

    it 'coerces ids and text fields to strings' do
      expect(numeric.fetch_message('7')).to include(id: '7', from: '1', to: '2', subject: '3', body: '4')
    end

    it 'finds a message by a non-string id' do
      expect(numeric.fetch_message(7)).to include(id: '7')
    end
  end

  describe '#inbox_message_ids_since' do
    it 'never reports new history' do
      expect(gmail.inbox_message_ids_since('100')).to eq([])
    end
  end

  describe '#inbox_message_ids_after' do
    it 'returns Gmail ids for messages on or after the start' do
      expect(gmail.inbox_message_ids_after(Time.utc(2026, 11, 4, 6, 0, 0))).to eq(%w[g2 g3])
    end

    it 'includes a message dated exactly at the start' do
      expect(gmail.inbox_message_ids_after(Time.utc(2026, 11, 2, 9, 0, 0))).to eq(%w[g1 g2 g3])
    end

    it 'excludes a message dated exactly at before' do
      ids = gmail.inbox_message_ids_after(Time.utc(2026, 11, 1), before: Time.utc(2026, 11, 6, 9, 0, 0))

      expect(ids).to eq(%w[g1 g2])
    end

    it 'applies no upper bound when before is nil' do
      expect(gmail.inbox_message_ids_after(Time.utc(2026, 11, 1), before: nil)).to eq(%w[g1 g2 g3])
    end

    it 'accepts dates as bounds' do
      ids = gmail.inbox_message_ids_after(Date.new(2026, 11, 3), before: Date.new(2026, 11, 5))

      expect(ids).to eq(%w[g2])
    end

    it 'returns uid_validity:uid ids for Yahoo' do
      expect(yahoo.inbox_message_ids_after(Time.utc(2026, 11, 3))).to eq(%w[7:5 7:3])
    end
  end

  describe '#inbox_status' do
    it 'reports uid_validity and the highest uid' do
      expect(yahoo.inbox_status).to have_attributes(uid_validity: 7, last_uid: 5)
    end

    it 'defaults uid_validity to 1 and last_uid to 0 for an empty mailbox' do
      expect(empty.inbox_status).to have_attributes(uid_validity: 1, last_uid: 0)
    end
  end

  describe '#inbox_uids_after' do
    it 'returns only uids strictly greater, sorted ascending' do
      expect(yahoo.inbox_uids_after(1)).to eq([ 3, 5 ])
    end

    it 'returns nothing when the last uid is the highest' do
      expect(yahoo.inbox_uids_after(5)).to eq([])
    end
  end

  describe '#inbox_uids_since' do
    it 'returns sorted uids on or after the start' do
      expect(yahoo.inbox_uids_since(Time.utc(2026, 11, 2, 9, 0, 0))).to eq([ 1, 3, 5 ])
    end

    it 'excludes uids dated at or after before' do
      expect(yahoo.inbox_uids_since(Time.utc(2026, 11, 1), before: Time.utc(2026, 11, 4, 9, 0, 0))).to eq([ 1 ])
    end

    it 'accepts dates as bounds' do
      expect(yahoo.inbox_uids_since(Date.new(2026, 11, 3), before: Date.new(2026, 11, 5))).to eq([ 3 ])
    end

    it 'applies no upper bound when before is nil' do
      expect(yahoo.inbox_uids_since(Time.utc(2026, 11, 3), before: nil)).to eq([ 3, 5 ])
    end
  end

  describe '#fetch_message' do
    it 'returns the message hash for a Gmail id' do
      expect(gmail.fetch_message('g2')).to eq(
        id: 'g2', provider: 'gmail', subject: 'Second', from: 'b@x.test', to: 'me@gmail.test',
        date: Time.utc(2026, 11, 4, 7, 0, 0), body: 'two', html_body: '<p>two</p>', source_url: nil,
        thread_id: nil, labels: [ 'INBOX' ]
      )
    end

    it 'returns the composite id and provider for Yahoo' do
      expect(yahoo.fetch_message('7:3')).to include(id: '7:3', provider: 'yahoo', subject: 'Y3')
    end

    it 'returns a nil html_body when the fixture has none' do
      expect(gmail.fetch_message('g3')[:html_body]).to be_nil
    end

    it 'returns the date as UTC' do
      expect(gmail.fetch_message('g2')[:date]).to be_utc
    end

    it 'raises when the message is unknown' do
      expect { gmail.fetch_message('nope') }.to raise_error(RuntimeError, 'Message not found: nope')
    end
  end

  describe '#attachments' do
    it 'lists attachment metadata with the byte size of the data' do
      expect(gmail.attachments('g1')).to eq([
        { id: 'a1', filename: 'cv.txt', mime_type: 'text/plain', size: 6 },
        { id: 'a2', filename: 'b.txt', mime_type: 'text/plain', size: 2 }
      ])
    end

    it 'measures the size in bytes, not characters' do
      expect(gmail.attachments('g2').pluck(:size)).to eq([ 5 ])
    end

    it 'returns an empty list for a message without attachments' do
      expect(gmail.attachments('g3')).to eq([])
    end

    it 'raises when the message is unknown' do
      expect { gmail.attachments('nope') }.to raise_error(RuntimeError, 'Message not found: nope')
    end
  end

  describe '#attachment' do
    it 'returns the data of the matching attachment' do
      expect(gmail.attachment('g1', 'a2')).to eq('bb')
    end

    it 'raises when the attachment is unknown' do
      expect { gmail.attachment('g1', 'zz') }.to raise_error(RuntimeError, 'Attachment not found: zz')
    end

    it 'raises when the message is unknown' do
      expect { gmail.attachment('nope', 'a1') }.to raise_error(RuntimeError, 'Message not found: nope')
    end
  end
end
