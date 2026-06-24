# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Emails::ProviderRegistry do
  subject(:registry) { described_class.new }

  let(:adapter) { Emails::Adapters::BaseAdapter.new }

  before { registry.register('gmail', adapter) }

  describe '#providers' do
    it 'returns the names of registered providers' do
      expect(registry.providers).to eq([ 'gmail' ])
    end
  end

  describe '#on_init' do
    it 'calls on_init on each registered adapter' do
      allow(adapter).to receive(:on_init)
      registry.on_init
      expect(adapter).to have_received(:on_init)
    end
  end

  describe '#on_exit' do
    it 'calls on_exit on each registered adapter' do
      allow(adapter).to receive(:on_exit)
      registry.on_exit
      expect(adapter).to have_received(:on_exit)
    end
  end

  describe '#fetch' do
    context 'when the provider is already registered' do
      it 'returns the registered adapter' do
        expect(registry.fetch('gmail')).to eq(adapter)
      end
    end

    context 'when the provider is not registered' do
      subject(:registry) { described_class.new('yahoo' => adapter_class) }

      let(:adapter_class) { class_double(Emails::Adapters::BaseAdapter, from_env: adapter) }

      it 'loads the adapter via from_env and returns it' do
        expect(registry.fetch('yahoo')).to eq(adapter)
        expect(adapter_class).to have_received(:from_env)
      end

      it 'calls from_env exactly once even when fetched twice (cached after first load)' do
        registry.fetch('yahoo')
        registry.fetch('yahoo')
        expect(adapter_class).to have_received(:from_env).once
      end

      it 'raises UnknownProviderError for a completely unknown name' do
        expect { registry.fetch('unknown') }
          .to raise_error(Emails::ProviderRegistry::UnknownProviderError, /unknown/)
      end

      it 'includes the available provider names in the error message' do
        expect { registry.fetch('unknown') }
          .to raise_error(Emails::ProviderRegistry::UnknownProviderError, /yahoo/)
      end
    end
  end
end
