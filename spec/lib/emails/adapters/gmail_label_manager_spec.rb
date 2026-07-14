require 'rails_helper'

RSpec.describe Emails::Adapters::GmailLabelManager do
  let(:service) { instance_double(Google::Apis::GmailV1::GmailService) }
  let(:labels) do
    [
      { id: 'INBOX', name: 'INBOX', type: 'system' },
      { id: 'Label_1', name: 'applications', type: 'user' }
    ]
  end
  let(:labels_provider) { -> { labels } }

  subject(:manager) { described_class.new(service: service, labels_provider: labels_provider) }

  describe '#modify_labels' do
    it 'adds labels to a message and returns the updated label list' do
      message = Google::Apis::GmailV1::Message.new(id: 'msg1', label_ids: [ 'INBOX', 'Label_1' ])
      allow(service).to receive(:modify_message)
        .with('me', 'msg1', an_instance_of(Google::Apis::GmailV1::ModifyMessageRequest))
        .and_return(message)

      result = manager.modify_labels('msg1', add: [ 'Label_1' ])

      expect(result).to eq(id: 'msg1', labels: [ 'INBOX', 'Label_1' ])
    end

    it 'raises when the message is not found' do
      allow(service).to receive(:modify_message).and_return(nil)

      expect { manager.modify_labels('missing') }.to raise_error('Message not found: missing')
    end

    it 'returns empty labels when a label-conflict client error occurs' do
      allow(service).to receive(:modify_message)
        .and_raise(Google::Apis::ClientError.new('Label name exists or conflicts'))

      result = manager.modify_labels('msg1', add: [ 'Label_1' ])

      expect(result).to eq(id: 'msg1', labels: [])
    end

    it 're-raises non-conflict client errors' do
      allow(service).to receive(:modify_message).and_raise(Google::Apis::ClientError.new('boom'))

      expect { manager.modify_labels('msg1', add: [ 'Label_1' ]) }
        .to raise_error(Google::Apis::ClientError, 'boom')
    end
  end

  describe '#create_label' do
    it 'creates and returns a new label' do
      created = Google::Apis::GmailV1::Label.new(id: 'Label_2', name: 'job-applications', type: 'user')
      allow(service).to receive(:create_user_label)
        .with('me', an_instance_of(Google::Apis::GmailV1::Label))
        .and_return(created)

      expect(manager.create_label(name: 'job-applications'))
        .to eq(id: 'Label_2', name: 'job-applications', type: 'user')
    end

    it 'returns the existing label when the name already exists' do
      allow(service).to receive(:create_user_label)
        .and_raise(Google::Apis::ClientError.new('Label name exists or conflicts'))

      expect(manager.create_label(name: 'applications'))
        .to eq(id: 'Label_1', name: 'applications', type: 'user')
    end

    it 're-raises non-conflict client errors' do
      allow(service).to receive(:create_user_label).and_raise(Google::Apis::ClientError.new('boom'))

      expect { manager.create_label(name: 'x') }.to raise_error(Google::Apis::ClientError, 'boom')
    end

    it 'raises when the create result is missing required fields' do
      allow(service).to receive(:create_user_label)
        .and_return(Google::Apis::GmailV1::Label.new(id: nil, name: 'x', type: 'user'))

      expect { manager.create_label(name: 'x') }.to raise_error('Label create error: x')
    end
  end

  describe '#build_label_ids' do
    it 'resolves label names and ids to their canonical ids' do
      expect(manager.build_label_ids([ 'INBOX', 'applications', 'unknown' ])).to eq([ 'INBOX', 'Label_1' ])
    end

    it 'accepts a single label id or name' do
      expect(manager.build_label_ids('applications')).to eq([ 'Label_1' ])
    end
  end
end
