require "rails_helper"

# Covers the N+1 gate in spec/support/prosopite.rb. These examples drive their
# own scan, since the gate's error is raised when a scan finishes.
RSpec.describe "N+1 query gate", prosopite: false do # rubocop:disable RSpec/DescribeClass
  after { Prosopite.finish }

  it "fails on an N+1 query" do
    create_list(:orchestration_step, 3)

    Prosopite.scan
    Orchestration::Step.find_each(&:pipeline)

    expect { Prosopite.finish }.to raise_error(Prosopite::NPlusOneQueriesError, /SELECT "orchestration_pipelines"/)
  end

  it "ignores queries run by FactoryBot" do
    Prosopite.scan
    create_list(:orchestration_step, 3)

    expect { Prosopite.finish }.not_to raise_error
  end
end
