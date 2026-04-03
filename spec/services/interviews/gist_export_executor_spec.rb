require 'rails_helper'

RSpec.describe Interviews::GistExportExecutor do
  describe '.call' do
    let(:gist_id) { 'test_gist_id' }

    it 'calls GistExportService with gist_id from input' do
      service = instance_double(Interviews::GistExportService)
      result = Interviews::GistExportService::Result.new(ok: true, message: 'Success')

      allow(Interviews::GistExportService).to receive(:new).with(ids: nil, gist_id: gist_id).and_return(service)
      allow(service).to receive(:call).and_return(result)

      output = described_class.call({ "gist_id" => gist_id })
      expect(output).to eq({ "ok" => true, "message" => "Success" })
    end

    it 'calls GistExportService with gist_id from ENV if not in input' do
      allow(ENV).to receive(:fetch).with("GIST_ID", nil).and_return(gist_id)
      service = instance_double(Interviews::GistExportService)
      result = Interviews::GistExportService::Result.new(ok: true, message: 'Success')

      allow(Interviews::GistExportService).to receive(:new).with(ids: nil, gist_id: gist_id).and_return(service)
      allow(service).to receive(:call).and_return(result)

      output = described_class.call({})
      expect(output).to eq({ "ok" => true, "message" => "Success" })
    end

    it 'returns skipped if gist_id is missing' do
      allow(ENV).to receive(:fetch).with("GIST_ID", nil).and_return(nil)

      output = described_class.call({})
      expect(output).to eq({ "skipped" => true, "reason" => "GIST_ID not configured" })
    end
  end
end
