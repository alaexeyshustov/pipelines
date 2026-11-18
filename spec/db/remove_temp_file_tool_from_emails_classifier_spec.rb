require "rails_helper"

# Assumes the planned data migration db/migrate/<timestamp>_remove_temp_file_tool_from_emails_classifier.rb defining
# RemoveTempFileToolFromEmailsClassifier (GH #299). The timestamp is unknown until it is written, so the file is globbed.
MIGRATION_FILE = Dir[Rails.root.join("db/migrate/*_remove_temp_file_tool_from_emails_classifier.rb").to_s].first
require MIGRATION_FILE if MIGRATION_FILE

RSpec.describe "RemoveTempFileToolFromEmailsClassifier migration", prosopite: false do # rubocop:disable RSpec/DescribeClass
  let(:migration_class) do
    raise "db/migrate/*_remove_temp_file_tool_from_emails_classifier.rb does not exist yet" unless MIGRATION_FILE

    RemoveTempFileToolFromEmailsClassifier
  end

  let(:classifier_name) { "Orchestration::Agents::EmailsClassifier" }

  def migrate_up = ActiveRecord::Migration.suppress_messages { migration_class.new.migrate(:up) }

  def tools_of(name) = Orchestration::Agent.find_by!(name: name).tools

  before { Orchestration::Agent.where(name: classifier_name).delete_all }

  it "removes Records::TempFileTool from the stored classifier tools" do
    create(:orchestration_agent, name: classifier_name, tools: [ "Records::TempFileTool" ])

    migrate_up

    expect(tools_of(classifier_name)).to be_blank
  end

  it "keeps the classifier's other tools" do
    create(:orchestration_agent, name: classifier_name, tools: [ "Records::TempFileTool", "Records::ReadRowsTool" ])

    migrate_up

    expect(tools_of(classifier_name)).to eq([ "Records::ReadRowsTool" ])
  end

  it "leaves other agents unchanged, including ones that use the tool" do
    other = create(:orchestration_agent, name: "Custom::Agent", tools: [ "Records::TempFileTool", "Records::ReadRowsTool" ])
    create(:orchestration_agent, name: classifier_name, tools: [ "Records::TempFileTool" ])

    migrate_up

    expect(other.reload.tools).to eq([ "Records::TempFileTool", "Records::ReadRowsTool" ])
  end

  it "does nothing when the classifier has no tools stored" do
    create(:orchestration_agent, name: classifier_name, tools: nil)

    expect { migrate_up }.not_to raise_error
    expect(tools_of(classifier_name)).to be_blank
  end

  it "does nothing when the classifier agent row does not exist" do
    expect { migrate_up }.not_to raise_error
  end

  it "is idempotent" do
    create(:orchestration_agent, name: classifier_name, tools: [ "Records::TempFileTool", "Records::ReadRowsTool" ])

    2.times { migrate_up }

    expect(tools_of(classifier_name)).to eq([ "Records::ReadRowsTool" ])
  end
end
