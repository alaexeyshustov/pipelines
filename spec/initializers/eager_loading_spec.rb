require "rails_helper"

RSpec.describe "Eager loading" do # rubocop:disable RSpec/DescribeClass
  it "loads all application constants without NameError" do
    expect { Rails.application.eager_load! }.not_to raise_error
  end
end
