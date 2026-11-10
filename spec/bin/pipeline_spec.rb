require "rails_helper"
require "open3"

RSpec.describe "bin/pipeline" do # rubocop:disable RSpec/DescribeClass
  def run_cli(*args)
    Open3.capture2e({ "RAILS_ENV" => "test" }, Rails.root.join("bin/pipeline").to_s, *args)
  end

  it "accepts --providers as a comma-separated list" do
    output, = run_cli("test", "--providers", "nope,nada")

    expect(output).to include("ERROR: Unknown provider 'nope'")
  end

  it "accepts a single --providers value" do
    output, = run_cli("test", "--providers", "nope")

    expect(output).to include("ERROR: Unknown provider 'nope'")
  end

  it "sets up providers given with --providers" do
    output, = run_cli("setup", "--providers", "nope")

    expect(output).to include("No setup instructions for 'nope'")
  end
end
