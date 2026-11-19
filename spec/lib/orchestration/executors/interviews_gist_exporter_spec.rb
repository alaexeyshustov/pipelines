require 'rails_helper'

RSpec.describe Orchestration::Executors::InterviewsGistExporter do
  describe '.call' do
    it 'delegates to GistExportService.call(ids: nil) when GIST_ID is set' do
      allow(ENV).to receive(:fetch).with("GIST_ID", nil).and_return('abc123')
      result = Interviews::GistExportService::Result.new(ok: true, message: 'Success')
      allow(Interviews::GistExportService).to receive(:call).with(ids: nil).and_return(result)

      expect(described_class.call).to eq({ "ok" => true, "message" => "Success" })
    end

    it 'ignores a stored gist_id input and skips when GIST_ID is unset' do
      allow(ENV).to receive(:fetch).with("GIST_ID", nil).and_return(nil)

      expect(described_class.call(gist_id: 'abc123'))
        .to eq({ "skipped" => true, "reason" => "GIST_ID not configured" })
    end

    it 'returns skipped when GIST_ID is unset' do
      allow(ENV).to receive(:fetch).with("GIST_ID", nil).and_return(nil)

      expect(described_class.call).to eq({ "skipped" => true, "reason" => "GIST_ID not configured" })
    end

    it 'returns skipped when GIST_ID is an empty string' do
      allow(ENV).to receive(:fetch).with("GIST_ID", nil).and_return('')
      allow(Interviews::GistExportService).to receive(:call)

      expect(described_class.call).to eq({ "skipped" => true, "reason" => "GIST_ID not configured" })
      expect(Interviews::GistExportService).not_to have_received(:call)
    end

    it 'uses the ENV gist, not the stored gist_id input' do
      allow(ENV).to receive(:fetch).with("GIST_ID", nil).and_return('abc123')
      result = Interviews::GistExportService::Result.new(ok: true, message: 'Success')
      allow(Interviews::GistExportService).to receive(:call).with(ids: nil).and_return(result)

      described_class.call(gist_id: 'deadbeef')
      expect(Interviews::GistExportService).to have_received(:call).with(ids: nil)
    end

    describe '.input_schema' do
      it 'is nil' do
        expect(described_class.input_schema).to be_nil
      end
    end
  end
end
