# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Seeds: pipeline 2 step input_mapping" do # rubocop:disable RSpec/DescribeClass
  before { load Rails.root.join("db/seeds.rb") }

  let(:pipeline) { Orchestration::Pipeline.find_by!(name: "Applications Workflow") }

  def step_action_for(step_name)
    pipeline.steps.find_by!(name: step_name).step_actions.first!
  end

  describe "Fetch Emails (step 1)" do
    subject(:sa) { step_action_for("Fetch Emails") }

    it "maps date from initial input" do
      expect(sa.input_mapping).to include("date" => { "from" => "_initial", "path" => "date" })
    end

    it "maps providers from initial input" do
      expect(sa.input_mapping).to include("providers" => { "from" => "_initial", "path" => "providers" })
    end
  end

  describe "Classify Emails (step 2)" do
    subject(:sa) { step_action_for("Classify Emails") }

    it "maps emails from fetch_emails output" do
      expect(sa.input_mapping).to include("emails" => { "from" => "fetch_emails", "path" => "emails" })
    end
  end

  describe "Filter Emails (step 3)" do
    subject(:sa) { step_action_for("Filter Emails") }

    it "has topic param set to job applications" do
      expect(sa.params).to include("topic" => "job applications")
    end

    it "maps emails from classify_emails results" do
      expect(sa.input_mapping).to include("emails" => { "from" => "classify_emails", "path" => "results" })
    end
  end

  describe "Ingest Emails (step 4)" do
    subject(:sa) { step_action_for("Ingest Emails") }

    it "maps emails from fetch_emails output" do
      expect(sa.input_mapping).to include("emails" => { "from" => "fetch_emails", "path" => "emails" })
    end

    it "maps results from filter_emails output" do
      expect(sa.input_mapping).to include("results" => { "from" => "filter_emails", "path" => "results" })
    end
  end

  describe "Export to Gist (step 10)" do
    subject(:sa) { step_action_for("Export to Gist") }

    it "has explicit non-nil input_mapping" do
      expect(sa.input_mapping).not_to be_nil
    end
  end
end
