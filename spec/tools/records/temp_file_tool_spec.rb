require 'rails_helper'

RSpec.describe Records::TempFileTool do
  subject(:tool) { described_class.new }

  let(:scratch_dir) { Pathname.new(Dir.mktmpdir('agent_scratch')) }
  let(:filename)    { "test_manage_#{SecureRandom.hex(4)}.txt" }
  let(:path)        { scratch_dir.join(filename) }

  around do |example|
    original = described_class.scratch_dir
    described_class.scratch_dir = scratch_dir
    example.run
  ensure
    described_class.scratch_dir = original
    FileUtils.rm_rf(scratch_dir)
  end

  describe 'write action' do
    it 'writes content to a file and confirms success' do
      result = tool.execute(action: 'write', filename: filename, content: 'hello world')
      expect(result).to include('written successfully')
      expect(File.read(path)).to eq('hello world')
    end

    it 'creates the scratch directory when it is missing' do
      FileUtils.rm_rf(scratch_dir)
      tool.execute(action: 'write', filename: filename, content: 'hello')
      expect(File.read(path)).to eq('hello')
    end

    it 'returns an error when content is blank' do
      result = tool.execute(action: 'write', filename: filename, content: '   ')
      expect(result).to include('Content is required')
    end

    it 'returns an error when content is nil' do
      result = tool.execute(action: 'write', filename: filename, content: nil)
      expect(result).to include('Content is required')
    end

    it 'accepts content of exactly 100 KB' do
      result = tool.execute(action: 'write', filename: filename, content: 'a' * 100.kilobytes)
      expect(result).to include('written successfully')
    end

    it 'rejects content over 100 KB and writes nothing' do
      result = tool.execute(action: 'write', filename: filename, content: 'a' * (100.kilobytes + 1))
      expect(result).to be_a(String).and match(/too large|100 KB/i)
      expect(path).not_to exist
    end

    it 'counts bytes, not characters, for the size cap' do
      result = tool.execute(action: 'write', filename: filename, content: 'é' * (60.kilobytes))
      expect(result).to match(/too large|100 KB/i)
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

    it 'returns an error string instead of raising when the name is a directory' do
      FileUtils.mkdir_p(described_class.scratch_dir.join('subdir'))
      result = tool.execute(action: 'delete', filename: 'subdir')
      expect(result).to be_a(String).and match(/cannot delete subdir/i)
    end
  end

  describe 'unknown action' do
    it 'returns an error message' do
      result = tool.execute(action: 'fly', filename: filename)
      expect(result).to include("Unknown action 'fly'")
    end
  end

  describe 'filename validation' do
    let(:outside) { Pathname.new(Dir.mktmpdir('outside')) }

    after { FileUtils.rm_rf(outside) }

    actions = %w[read write delete]

    [ '../x', '/etc/passwd', 'a/b', '.env', '', 'a' * 65, "name\0.txt", '..', '-leading-dash', 'sp ace.txt' ].each do |bad|
      actions.each do |action|
        it "rejects #{bad.inspect} for #{action}" do
          result = tool.execute(action: action, filename: bad, content: 'x')
          expect(result).to be_a(String).and match(/invalid filename/i)
        end
      end
    end

    it 'does not write outside the scratch directory for a traversal name' do
      target = outside.join('x')
      tool.execute(action: 'write', filename: "../#{outside.basename}/x", content: 'pwned')
      expect(target).not_to exist
    end

    it 'accepts a 64 character name' do
      result = tool.execute(action: 'write', filename: "a#{'b' * 63}", content: 'x')
      expect(result).to include('written successfully')
    end

    it 'accepts dots, dashes and underscores after the first character' do
      result = tool.execute(action: 'write', filename: 'out_put-1.v2.txt', content: 'x')
      expect(result).to include('written successfully')
    end
  end

  describe 'symlinks' do
    let(:secret_dir) { Pathname.new(Dir.mktmpdir('secret')) }
    let(:secret)     { secret_dir.join('secret.txt') }

    before do
      File.write(secret, 'top secret')
      File.symlink(secret, path)
    end

    after { FileUtils.rm_rf(secret_dir) }

    it 'refuses to read through a symlink' do
      result = tool.execute(action: 'read', filename: filename)
      expect(result).not_to include('top secret')
    end

    it 'refuses to write through a symlink' do
      tool.execute(action: 'write', filename: filename, content: 'overwritten')
      expect(File.read(secret)).to eq('top secret')
    end

    it 'reports an error string rather than raising' do
      expect(tool.execute(action: 'read', filename: filename)).to be_a(String)
    end
  end

  describe '.scratch_dir' do
    it 'defaults to tmp/agent_scratch under the Rails root' do
      described_class.scratch_dir = nil
      expect(described_class.scratch_dir.to_s).to eq(Rails.root.join('tmp/agent_scratch').to_s)
    end

    it 'is not the repo root or the system /tmp' do
      expect(described_class.description).not_to include('/tmp')
    end
  end
end
