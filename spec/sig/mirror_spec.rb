require "spec_helper"

RSpec.describe "sig/ mirrors the source tree" do # rubocop:disable RSpec/DescribeClass
  let(:root) { File.expand_path("../..", __dir__) }

  it "has a source file for every app/ and lib/ signature" do
    orphans = Dir.glob("sig/{app,lib}/**/*.rbs", base: root).reject do |sig|
      File.exist?(File.join(root, sig.delete_prefix("sig/").delete_suffix(".rbs") + ".rb"))
    end

    expect(orphans).to be_empty, "move shims to sig/shims/ or delete stale signatures: #{orphans.join(', ')}"
  end
end
