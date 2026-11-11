require 'rails_helper'

RSpec.describe Emails::Adapters::BaseAdapter do
  subject(:adapter) { described_class.new }

  describe '.from_env' do
    it 'raises NotImplementedError' do
      expect { described_class.from_env }.to raise_error(NotImplementedError, /from_env is not implemented/)
    end
  end

  describe '#list_messages' do
    it 'raises NotImplementedError' do
      expect { adapter.list_messages }.to raise_error(NotImplementedError, /list_messages is not implemented/)
    end
  end

  describe '#get_message' do
    it 'raises NotImplementedError' do
      expect { adapter.get_message('id') }.to raise_error(NotImplementedError, /get_message is not implemented/)
    end
  end

  describe '#search_messages' do
    it 'raises NotImplementedError' do
      expect { adapter.search_messages('query') }.to raise_error(NotImplementedError, /search_messages is not implemented/)
    end
  end

  describe '#get_labels' do
    it 'raises NotImplementedError' do
      expect { adapter.get_labels }.to raise_error(NotImplementedError, /get_labels is not implemented/)
    end
  end

  describe '#get_unread_count' do
    it 'raises NotImplementedError' do
      expect { adapter.get_unread_count }.to raise_error(NotImplementedError, /get_unread_count is not implemented/)
    end
  end

  describe '#modify_labels' do
    it 'raises NotImplementedError' do
      expect { adapter.modify_labels('id') }.to raise_error(NotImplementedError, /modify_labels is not implemented/)
    end
  end

  describe '#create_label' do
    it 'raises NotImplementedError' do
      expect { adapter.create_label(name: 'label') }.to raise_error(NotImplementedError, /create_label is not implemented/)
    end
  end

  {
    attachment: [ 'm1', 'a1' ], attachments: [ 'm1' ], profile: [], inbox_message_ids_since: [ 'h1' ],
    inbox_message_ids_after: [ Date.new(2026, 1, 1) ], account: [], inbox_status: [], inbox_uids_after: [ 1 ],
    inbox_uids_since: [ Date.new(2026, 1, 1) ], fetch_message: [ 'm1' ]
  }.each do |method_name, args|
    describe "##{method_name}" do
      it 'raises NotImplementedError' do
        expect { adapter.public_send(method_name, *args) }.to raise_error(NotImplementedError, /#{method_name} is not implemented/)
      end
    end
  end
end
