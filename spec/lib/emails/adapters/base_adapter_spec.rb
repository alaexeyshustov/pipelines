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

  describe '#message' do
    it 'raises NotImplementedError' do
      expect { adapter.message('id') }.to raise_error(NotImplementedError, /message is not implemented/)
    end
  end

  describe '#search_messages' do
    it 'raises NotImplementedError' do
      expect { adapter.search_messages('query') }.to raise_error(NotImplementedError, /search_messages is not implemented/)
    end
  end

  describe '#labels' do
    it 'raises NotImplementedError' do
      expect { adapter.labels }.to raise_error(NotImplementedError, /labels is not implemented/)
    end
  end

  describe '#unread_count' do
    it 'raises NotImplementedError' do
      expect { adapter.unread_count }.to raise_error(NotImplementedError, /unread_count is not implemented/)
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
end
