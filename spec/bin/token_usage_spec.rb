# rubocop:disable RSpec/DescribeClass
require "open3"
require "tmpdir"
require "json"

RSpec.describe "bin/token-usage.sh" do
  let(:script) { File.expand_path("../../bin/token-usage.sh", __dir__) }

  def run(path = nil)
    args = path ? [ script, path ] : [ script ]
    stdout, _stderr, _status = Open3.capture3(*args)
    stdout.chomp
  end

  def write_transcript(entries, dir: Dir.mktmpdir)
    path = File.join(dir, "session.jsonl")
    File.write(path, entries.map { JSON.generate(_1) }.join("\n"))
    path
  end

  def usage_entry(id:, input:, output:, cache_read: 0, cache_write: 0)
    {
      type: "assistant",
      message: {
        id: id,
        usage: {
          input_tokens: input,
          output_tokens: output,
          cache_read_input_tokens: cache_read,
          cache_creation_input_tokens: cache_write
        }
      }
    }
  end

  context "when transcript path does not exist" do
    it 'returns "unavailable"' do
      expect(run("/nonexistent/path/session.jsonl")).to eq("unavailable")
    end
  end

  context "when transcript has no usage entries" do
    it "returns zeros for all counters" do
      path = write_transcript([ { type: "permission-mode", permissionMode: "default" } ])
      expect(run(path)).to eq("input=0, output=0, cache_read=0, cache_write=0")
    end
  end

  context "when transcript has one usage entry" do
    it "returns the exact token counts" do
      path = write_transcript([ usage_entry(id: "msg_1", input: 100, output: 50, cache_read: 200, cache_write: 300) ])
      expect(run(path)).to eq("input=100, output=50, cache_read=200, cache_write=300")
    end
  end

  context "when transcript has multiple usage entries with distinct IDs" do
    it "sums token counts across all entries" do
      path = write_transcript([
        usage_entry(id: "msg_1", input: 100, output: 50, cache_read: 200, cache_write: 300),
        usage_entry(id: "msg_2", input: 50, output: 75, cache_read: 100, cache_write: 150)
      ])
      expect(run(path)).to eq("input=150, output=125, cache_read=300, cache_write=450")
    end
  end

  context "when transcript has duplicate message IDs" do
    it "counts each unique message only once" do
      path = write_transcript([
        usage_entry(id: "msg_1", input: 100, output: 50),
        usage_entry(id: "msg_1", input: 100, output: 50),
        usage_entry(id: "msg_2", input: 40, output: 20)
      ])
      expect(run(path)).to eq("input=140, output=70, cache_read=0, cache_write=0")
    end
  end
end
# rubocop:enable RSpec/DescribeClass
