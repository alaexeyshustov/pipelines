require "rails_helper"

RSpec.describe Orchestration::PipelineImporter do
  def agent_hash(overrides = {})
    {
      "name" => "Importer::Agent", "description" => "d", "model" => "gpt-4o", "tools" => [ "Records::ListRowsTool" ],
      "enabled" => true, "prompt" => "Do it", "output_schema" => { "type" => "object" }, "input_schema" => { "type" => "object" }
    }.merge(overrides)
  end

  def action_hash(overrides = {})
    { "name" => "Fetch", "description" => nil, "kind" => "agent", "agent_class" => nil, "agent" => agent_hash }.merge(overrides)
  end

  def step_action_hash(overrides = {})
    { "output_key" => "fetched", "input_mapping" => {}, "action" => action_hash }.merge(overrides)
  end

  def pipeline_hash(overrides = {})
    {
      "name" => "Imported", "description" => "desc", "enabled" => true, "cron_expression" => "0 9 * * *",
      "model" => "gpt-4o", "initial_input_schema" => { "type" => "object" },
      "steps" => [ { "name" => "Step A", "enabled" => true, "step_actions" => [ step_action_hash ] } ]
    }.merge(overrides)
  end

  def envelope(*pipelines)
    { "format" => "pipeline_export", "schema_version" => 1, "pipelines" => pipelines }
  end

  describe ".call" do
    it "creates a pipeline with its steps", :aggregate_failures do
      result = described_class.call(envelope(pipeline_hash))

      expect(result.errors).to eq([])
      pipeline = result.pipelines.sole
      expect(pipeline).to be_persisted
      expect(pipeline).to have_attributes(name: "Imported", description: "desc", cron_expression: "0 9 * * *", model: "gpt-4o",
                                          initial_input_schema: { "type" => "object" })
      expect(pipeline.steps.sole.name).to eq("Step A")
    end

    it "creates step actions, actions and agent", :aggregate_failures do
      sa = described_class.call(envelope(pipeline_hash)).pipelines.sole.steps.sole.step_actions.sole

      expect(sa).to have_attributes(output_key: "fetched", input_mapping: {})
      expect(sa.action).to have_attributes(name: "Fetch", kind: "agent")
      expect(sa.action.agent).to have_attributes(name: "Importer::Agent")
    end

    it "always creates pipelines disabled" do
      result = described_class.call(envelope(pipeline_hash("enabled" => true)))

      expect(result.pipelines.sole.enabled).to be(false)
    end

    it "derives 1-based positions from array order" do
      steps = [
        { "name" => "One", "enabled" => true, "step_actions" => [
          step_action_hash("output_key" => "a"), step_action_hash("output_key" => "b")
        ] },
        { "name" => "Two", "enabled" => false, "step_actions" => [] }
      ]
      pipeline = described_class.call(envelope(pipeline_hash("steps" => steps))).pipelines.sole

      expect(pipeline.steps.map { |s| [ s.name, s.position, s.enabled ] }).to eq([ [ "One", 1, true ], [ "Two", 2, false ] ])
      expect(pipeline.steps.first.step_actions.map { |sa| [ sa.output_key, sa.position ] }).to eq([ [ "a", 1 ], [ "b", 2 ] ])
    end

    it "imports multiple pipelines" do
      result = described_class.call(envelope(pipeline_hash("name" => "P1"), pipeline_hash("name" => "P2", "steps" => [])))

      expect(result.pipelines.map(&:name)).to eq(%w[P1 P2])
    end

    it "renames on name collision" do
      create(:orchestration_pipeline, name: "Imported")

      first = described_class.call(envelope(pipeline_hash)).pipelines.sole
      second = described_class.call(envelope(pipeline_hash)).pipelines.sole

      expect([ first.name, second.name ]).to eq([ "Imported (2)", "Imported (3)" ])
      expect(Orchestration::Pipeline.where(name: "Imported").count).to eq(1)
    end

    it "reuses an existing agent without modifying it" do
      existing = create(:orchestration_agent, name: "Importer::Agent", prompt: "original", model: "x")

      result = described_class.call(envelope(pipeline_hash))

      expect(result.pipelines.sole.steps.first.step_actions.first.action.agent).to eq(existing)
      expect(existing.reload).to have_attributes(prompt: "original", model: "x")
      expect(Orchestration::Agent.count).to eq(1)
    end

    it "creates a new agent with all settings" do
      described_class.call(envelope(pipeline_hash))

      expect(Orchestration::Agent.find_by!(name: "Importer::Agent")).to have_attributes(
        description: "d", model: "gpt-4o", tools: [ "Records::ListRowsTool" ], enabled: true, prompt: "Do it",
        output_schema: { "type" => "object" }, input_schema: { "type" => "object" }
      )
    end

    it "always creates new action rows" do
      2.times { described_class.call(envelope(pipeline_hash("name" => "X"))) }

      expect(Orchestration::Action.count).to eq(2)
    end

    it "decodes service action keywords into class names" do
      sa = step_action_hash("action" => action_hash("kind" => "service", "agent" => nil, "agent_class" => "agent_query"))
      steps = [ { "name" => "S", "enabled" => true, "step_actions" => [ sa ] } ]

      result = described_class.call(envelope(pipeline_hash("steps" => steps)))

      expect(result.errors).to eq([])
      expect(Orchestration::Action.sole.agent_class).to eq("Orchestration::Executors::Query")
    end

    it "returns an error for an unknown keyword" do
      sa = step_action_hash("action" => action_hash("kind" => "service", "agent" => nil, "agent_class" => "agent_nope"))
      steps = [ { "name" => "S", "enabled" => true, "step_actions" => [ sa ] } ]

      result = described_class.call(envelope(pipeline_hash("steps" => steps)))

      expect(result.pipelines).to eq([])
      expect(result.errors.join).to include("agent_nope", "Imported", "step \"S\"")
      expect(Orchestration::Pipeline.count).to eq(0)
    end

    it "returns an error for an invalid input_mapping reference" do
      sa = step_action_hash("input_mapping" => { "x" => { "from" => "ghost" } })
      steps = [ { "name" => "S", "enabled" => true, "step_actions" => [ sa ] } ]

      result = described_class.call(envelope(pipeline_hash("steps" => steps)))

      expect(result.pipelines).to eq([])
      expect(result.errors.join).to include("ghost")
      expect(Orchestration::Pipeline.count).to eq(0)
    end

    it "returns an error for an invalid cron expression" do
      result = described_class.call(envelope(pipeline_hash("cron_expression" => "nonsense")))

      expect(result.pipelines).to eq([])
      expect(result.errors.join).to include("cron")
    end

    it "returns an error for an invalid agent tool" do
      result = described_class.call(envelope(pipeline_hash("steps" => [ { "name" => "S", "step_actions" => [
        step_action_hash("action" => action_hash("agent" => agent_hash("tools" => [ "Kernel" ])))
      ] } ])))

      expect(result.errors.join).to include("Kernel")
      expect(Orchestration::Agent.count).to eq(0)
    end

    [ nil, "str", [], 3, {}, { "format" => "other", "pipelines" => [] }, { "format" => "pipeline_export" },
      { "format" => "pipeline_export", "pipelines" => {} }, { "format" => "pipeline_export", "pipelines" => [ 1 ] },
      { "format" => "pipeline_export", "pipelines" => [ { "name" => "P", "steps" => {} } ] },
      { "format" => "pipeline_export", "pipelines" => [ { "name" => "P", "steps" => [ "x" ] } ] },
      { "format" => "pipeline_export", "pipelines" => [ { "name" => "P", "steps" => [ { "name" => "S", "step_actions" => [ [] ] } ] } ] },
      { "format" => "pipeline_export", "pipelines" => [ { "name" => "P", "steps" => [ { "name" => "S", "step_actions" => [
        { "output_key" => "a", "action" => { "name" => "A", "kind" => "bogus" } }
      ] } ] } ] } ].each do |bad|
      it "returns errors without raising for #{bad.inspect}", :aggregate_failures do
        result = nil
        expect { result = described_class.call(bad) }.not_to raise_error
        expect(result.pipelines).to eq([])
        expect(result.errors).not_to be_empty
        expect(Orchestration::Pipeline.count).to eq(0)
      end
    end

    it "returns an error when agent tools is not an array" do
      steps = [ { "name" => "S", "step_actions" => [ step_action_hash("action" => action_hash("agent" => agent_hash("tools" => "Records::ListRowsTool"))) ] } ]

      result = described_class.call(envelope(pipeline_hash("steps" => steps)))

      expect(result.errors.join).to include("tools")
    end

    it "rolls back everything when a later pipeline is invalid", :aggregate_failures do
      result = described_class.call(envelope(pipeline_hash("name" => "Good"), pipeline_hash("name" => "Bad", "cron_expression" => "nonsense")))

      expect(result.pipelines).to eq([])
      expect(result.errors.join).to include("Bad")
      expect(Orchestration::Pipeline.count).to eq(0)
      expect(Orchestration::Agent.count).to eq(0)
      expect(Orchestration::Action.count).to eq(0)
    end

    it "ignores unknown keys and never assigns ids or timestamps", :aggregate_failures do
      data = pipeline_hash("id" => 999, "created_at" => "2000-01-01", "bogus" => 1)
      assign_ids(data, 998, 997, 996, 995)

      result = described_class.call(envelope(data))

      expect(result.errors).to eq([])
      pipeline = result.pipelines.sole
      step = pipeline.steps.first
      sa = step.step_actions.first
      expect([ pipeline.id, step.id, sa.id, sa.action.id, sa.action.agent.id ]).not_to include(999, 998, 997, 996, 995)
      expect(pipeline.created_at.year).to be >= 2024
    end
  end

  describe "round trip" do
    let(:pipeline) { create(:orchestration_pipeline, name: "Round trip", cron_expression: "0 9 * * *", model: "gpt-4o") }
    let(:step) { create(:orchestration_step, pipeline: pipeline, position: 1, name: "Fetch step") }
    let(:agent) { create(:orchestration_agent, name: "Trip::Agent", tools: [ "Records::ListRowsTool" ], prompt: "Do it") }

    before do
      fetcher = create(:orchestration_action, name: "Fetch", kind: "service", agent: nil, agent_class: "Orchestration::Executors::EmailsFetcher")
      create(:orchestration_step_action, step: step, position: 1, output_key: "fetched", action: fetcher,
                                         input_mapping: { "date" => { "from" => "_initial", "path" => "date" } })
      classify = create(:orchestration_step, pipeline: pipeline, position: 2, name: "Classify step")
      create(:orchestration_step_action, step: classify, position: 1, output_key: "classified",
                                         action: create(:orchestration_action, name: "Classify", agent: agent),
                                         input_mapping: { "emails" => { "from" => "fetched" } })
    end

    it "re-creates an exported pipeline that exports identically", :aggregate_failures do
      exported = Orchestration::PipelineExporter.call([ pipeline ])
      pipeline.destroy!

      result = described_class.call(JSON.parse(JSON.generate(exported)))

      expect(result.errors).to eq([])
      reexported = Orchestration::PipelineExporter.call(result.pipelines)
      expect(reexported["pipelines"].sole).to eq(exported["pipelines"].sole.merge("enabled" => false))
      expect(Orchestration::Agent.where(name: "Trip::Agent").count).to eq(1)
    end
  end

  def assign_ids(data, step_id, step_action_id, action_id, agent_id)
    step_data = data["steps"][0]
    step_action_data = step_data["step_actions"][0]
    step_data["id"] = step_id
    step_action_data["id"] = step_action_id
    step_action_data["action"]["id"] = action_id
    step_action_data["action"]["agent"]["id"] = agent_id
  end
end
