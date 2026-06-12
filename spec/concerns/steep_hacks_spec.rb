require 'rails_helper'

RSpec.describe SteepHacks do
  subject(:instance) { host_class.new }

  let(:host_class) { Class.new { include SteepHacks } }


  describe '#empty_object' do
    it 'returns an empty hash' do
      expect(instance.empty_object).to eq({})
    end
  end
end
