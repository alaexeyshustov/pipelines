# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Emails::ProviderRegistry do
  subject(:registry) { described_class.new }

  let(:adapter) { instance_double(Emails::Adapters::BaseAdapter) }

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
end
