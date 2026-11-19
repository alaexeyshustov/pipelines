require "rails_helper"

# Assumes the planned migration db/migrate/<timestamp>_add_active_to_evaluation_prompts.rb defining
# AddActiveToEvaluationPrompts (GH #301). The timestamp is unknown until it is written, so the file is globbed.
ADD_ACTIVE_MIGRATION_FILE = Dir[Rails.root.join("db/migrate/*_add_active_to_evaluation_prompts.rb").to_s].first
require ADD_ACTIVE_MIGRATION_FILE if ADD_ACTIVE_MIGRATION_FILE

RSpec.describe "AddActiveToEvaluationPrompts migration", prosopite: false do # rubocop:disable RSpec/DescribeClass
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration_class) do
    raise "db/migrate/*_add_active_to_evaluation_prompts.rb does not exist yet" unless ADD_ACTIVE_MIGRATION_FILE

    AddActiveToEvaluationPrompts
  end

  def run_migration(direction)
    ActiveRecord::Migration.suppress_messages { migration_class.new.migrate(direction) }
    Evaluation::Prompt.reset_column_information
  end

  def column_names = connection.columns("evaluation_prompts").map(&:name)

  def active_index_sql
    connection.select_value(
      "SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = 'evaluation_prompts' AND sql LIKE '%active%'"
    )
  end

  def insert_legacy_prompt(name:, version:, metadata:)
    connection.execute(<<~SQL.squish)
      INSERT INTO evaluation_prompts (name, version, system_prompt, user_prompt, metadata, created_at, updated_at)
      VALUES (#{connection.quote(name)}, #{version}, 's', 'u', #{connection.quote(metadata)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
  end

  def row(name, version)
    connection.select_one(
      "SELECT active, activated_at, metadata FROM evaluation_prompts WHERE name = #{connection.quote(name)} AND version = #{version}"
    )
  end

  # Bring the schema back to its pre-migration shape so the data backfill has something to do.
  before { run_migration(:down) if column_names.include?("active") }

  describe "up" do
    it "adds active (default false, not null) and a nullable activated_at" do
      run_migration(:up)

      active = connection.columns("evaluation_prompts").find { |c| c.name == "active" }
      activated_at = connection.columns("evaluation_prompts").find { |c| c.name == "activated_at" }
      expect(active).to have_attributes(null: false)
      expect(active.default.to_s).to match(/\A(0|false)\z/i)
      expect(activated_at.null).to be(true)
    end

    it "adds a partial unique index on name where active" do
      run_migration(:up)

      expect(active_index_sql).to match(/UNIQUE/i).and match(/\(\s*"?name"?\s*\)/).and match(/WHERE\s+"?active"?/i)
    end

    it "marks only the newest version per name active and stamps activated_at" do
      insert_legacy_prompt(name: "AgentA", version: 1, metadata: "{}")
      insert_legacy_prompt(name: "AgentA", version: 2, metadata: "{}")
      insert_legacy_prompt(name: "AgentB", version: 1, metadata: "{}")

      run_migration(:up)

      expect(row("AgentA", 2)).to include("active" => 1, "activated_at" => be_present)
      expect(row("AgentA", 1)).to include("active" => 0, "activated_at" => nil)
      expect(row("AgentB", 1)).to include("active" => 1)
    end

    it "breaks version ties by the highest id" do
      insert_legacy_prompt(name: "AgentA", version: 1, metadata: "{}")
      insert_legacy_prompt(name: "AgentA", version: 1, metadata: "{}")
      ids = connection.select_values("SELECT id FROM evaluation_prompts WHERE name = 'AgentA' ORDER BY id")

      run_migration(:up)

      expect(connection.select_values("SELECT id FROM evaluation_prompts WHERE active = 1")).to eq([ ids.last ])
    end

    it "strips the legacy $.active key from valid metadata and keeps the rest" do
      insert_legacy_prompt(name: "AgentA", version: 1, metadata: '{"active":true,"note":"keep"}')

      run_migration(:up)

      expect(JSON.parse(row("AgentA", 1)["metadata"])).to eq("note" => "keep")
    end

    it "succeeds and leaves non-JSON metadata untouched" do
      insert_legacy_prompt(name: "AgentA", version: 1, metadata: "not json")

      expect { run_migration(:up) }.not_to raise_error
      expect(row("AgentA", 1)["metadata"]).to eq("not json")
      expect(row("AgentA", 1)).to include("active" => 1)
    end

    it "succeeds on an empty table" do
      expect { run_migration(:up) }.not_to raise_error
    end
  end

  describe "down" do
    it "removes the columns and the index" do
      run_migration(:up)

      run_migration(:down)

      expect(column_names).not_to include("active", "activated_at")
      expect(active_index_sql).to be_nil
    end
  end
end
