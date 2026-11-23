require "rails_helper"
require "rake"

RSpec.describe "users:upsert" do # rubocop:disable RSpec/DescribeClass
  include RakeTaskHelpers

  let(:task) { Rake::Task["users:upsert"] }
  let(:password) { "s3cret-passw0rd-xyz" }

  around do |example|
    saved = ENV.values_at("ADMIN_EMAIL", "ADMIN_PASSWORD")
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_PASSWORD"] = password
    example.run
  ensure
    ENV["ADMIN_EMAIL"], ENV["ADMIN_PASSWORD"] = saved
  end

  before { load_rake_task("users:upsert") }

  # Runs the task and returns what it printed to stdout and stderr, plus whatever it raised.
  def run_task
    saved = [ $stdout, $stderr ]
    $stdout, $stderr = StringIO.new, StringIO.new
    { error: invoke_task, stdout: $stdout.string, stderr: $stderr.string }
  ensure
    $stdout, $stderr = saved
  end

  def invoke_task
    task.invoke
    nil
  rescue SystemExit, StandardError => e
    e
  end

  it "creates the user from the environment" do
    expect { run_task }.to change(User, :count).by(1)

    expect(User.authenticate_by(email_address: "admin@example.com", password:)).to be_present
  end

  it "does not duplicate the user on a second run" do
    run_task
    task.reenable

    expect { run_task }.not_to change(User, :count)
  end

  it "updates the password of the existing user on a rerun" do
    create(:user, email_address: "admin@example.com", password: "old-passw0rd")

    run_task

    expect(User.authenticate_by(email_address: "admin@example.com", password:)).to be_present
    expect(User.authenticate_by(email_address: "admin@example.com", password: "old-passw0rd")).to be_nil
  end

  it "never prints the password" do
    result = run_task

    expect(result[:error]).to be_nil
    expect(result.values_at(:stdout, :stderr).join).not_to include(password)
  end

  %w[ADMIN_EMAIL ADMIN_PASSWORD].each do |name|
    it "fails clearly when #{name} is missing" do
      ENV.delete(name)

      result = nil
      expect { result = run_task }.not_to change(User, :count)

      expect(result[:error]).to be_present
      expect([ result[:error].message, result[:stderr] ].join).to include(name)
    end

    it "fails clearly when #{name} is blank, without printing the password" do
      ENV[name] = ""

      result = run_task

      expect(result[:error]).to be_present
      expect([ result[:error].message, result[:stdout], result[:stderr] ].join).not_to include(password)
    end
  end
end
