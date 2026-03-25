require 'rails_helper'

RSpec.describe Records::TempFileTool do
  subject(:tool) { described_class.new }

  let(:filename) { "test_manage_#{SecureRandom.hex(4)}.txt" }
  let(:path)     { Rails.root.join('tmp', filename) }

  after { File.delete(path) if File.exist?(path) }

  describe 'write action' do
    it 'writes content to a file and confirms success' do
      result = tool.execute(action: 'write', filename: filename, content: 'hello world')
      expect(result).to include('written successfully')
      expect(File.read(path)).to eq('hello world')
    end

    it 'returns an error when content is blank' do
      result = tool.execute(action: 'write', filename: filename, content: '   ')
      expect(result).to include('Content is required')
    end

    it 'returns an error when content is nil' do
      result = tool.execute(action: 'write', filename: filename, content: nil)
      expect(result).to include('Content is required')
    end
  end

  describe 'read action' do
    before { File.write(path, 'stored content') }

    it 'reads and returns the file content' do
      result = tool.execute(action: 'read', filename: filename)
      expect(result).to eq('stored content')
    end

    it 'returns a not-found message for a missing file' do
      result = tool.execute(action: 'read', filename: 'nonexistent_file.txt')
      expect(result).to include('File not found')
    end
  end

  describe 'delete action' do
    before { File.write(path, 'to be deleted') }

    it 'deletes the file and confirms' do
      result = tool.execute(action: 'delete', filename: filename)
      expect(result).to include('deleted successfully')
      expect(File.exist?(path)).to be false
    end

    it 'returns a not-found message when the file does not exist' do
      result = tool.execute(action: 'delete', filename: 'ghost_file.txt')
      expect(result).to include('File not found')
    end
  end

  describe 'unknown action' do
    it 'returns an error message' do
      result = tool.execute(action: 'fly', filename: filename)
      expect(result).to include("Unknown action 'fly'")
    end
  end
end
