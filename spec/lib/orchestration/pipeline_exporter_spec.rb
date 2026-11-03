require "rails_helper"

RSpec.describe Orchestration::PipelineExporter do
  describe ".call" do
    it "wraps pipelines in a versioned envelope" do
      result = described_class.call([])

      expect(result).to eq("format" => "pipeline_export", "schema_version" => 1, "pipelines" => [])
    end

    it "exports pipeline settings" do
      schema = { "type" => "object", "properties" => { "q" => { "type" => "string" } } }
      pipeline = create(:orchestration_pipeline, name: "Daily", description: "d", enabled: false,
                        cron_expression: "0 9 * * *", model: "gpt-x", initial_input_schema: schema)

      exported = described_class.call([ pipeline ])["pipelines"].first

      expect(exported).to include(
        "name" => "Daily", "description" => "d", "enabled" => false,
        "cron_expression" => "0 9 * * *", "model" => "gpt-x", "initial_input_schema" => schema,
        "steps" => []
      )
    end

    context "with unordered steps and step actions" do
      let(:pipeline) { create(:orchestration_pipeline) }
      let(:mapping) { { "q" => { "from" => "_initial" } } }
      let(:steps) { described_class.call(Orchestration::Pipeline.where(id: pipeline.id)).dig("pipelines", 0, "steps") }

      before do
        second = create(:orchestration_step, pipeline: pipeline, name: "Second", position: 2, enabled: false)
        first = create(:orchestration_step, pipeline: pipeline, name: "First", position: 1)
        create(:orchestration_step_action, step: first, position: 2, output_key: "b")
        create(:orchestration_step_action, step: first, position: 1, output_key: "a", input_mapping: mapping)
        create(:orchestration_step_action, step: second, position: 1, output_key: "c")
      end

      it "orders steps by position" do
        expect(steps.pluck("name", "enabled")).to eq([ [ "First", true ], [ "Second", false ] ])
      end

      it "orders step actions by position and keeps input mapping" do
        expect(steps.first["step_actions"].pluck("output_key", "input_mapping")).to eq([ [ "a", mapping ], [ "b", nil ] ])
      end

      it "does not emit positions" do
        expect(steps.flat_map(&:keys) + steps.flat_map { |s| s["step_actions"].flat_map(&:keys) }).not_to include("position")
      end
    end

    it "exports a service-kind action with an agent class keyword and no agent" do
      action = create(:orchestration_action, :service_kind, name: "Fetch", description: "fetches",
                      agent_class: "Orchestration::Executors::EmailsFetcher")
      step_action = create(:orchestration_step_action, action: action)

      exported = described_class.call([ step_action.step.pipeline ])["pipelines"].first
      exported_action = exported.dig("steps", 0, "step_actions", 0, "action")

      expect(exported_action).to eq(
        "name" => "Fetch", "description" => "fetches", "kind" => "service",
        "agent_class" => "agent_emails_fetcher", "agent" => nil
      )
    end

    context "with an agent-kind action" do
      let(:agent) do
        create(:orchestration_agent, name: "Classifier", description: "classifies", model: "m1",
                                     tools: [ "Records::ListRowsTool" ], enabled: false, prompt: "Do it",
                                     output_schema: { "type" => "object" }, input_schema: { "type" => "string" })
      end
      let(:step_action) { create(:orchestration_step_action, action: create(:orchestration_action, name: "Classify", agent: agent)) }
      let(:exported_action) do
        described_class.call([ step_action.step.pipeline ]).dig("pipelines", 0, "steps", 0, "step_actions", 0, "action")
      end

      it "exports kind without an agent class" do
        expect(exported_action).to include("kind" => "agent", "agent_class" => nil)
      end

      it "embeds all agent settings" do
        expect(exported_action["agent"]).to eq(
          "name" => "Classifier", "description" => "classifies", "model" => "m1",
          "tools" => [ "Records::ListRowsTool" ], "enabled" => false, "prompt" => "Do it",
          "output_schema" => { "type" => "object" }, "input_schema" => { "type" => "string" }
        )
      end
    end

    context "with several pipelines" do
      let(:pipelines) do
        Array.new(3) do
          step_action = create(:orchestration_step_action)
          create(:orchestration_step_action, step: step_action.step, position: step_action.position + 100)
          step_action.step.pipeline
        end
      end

      it "exports every pipeline in order" do
        result = described_class.call(pipelines)

        expect(result["pipelines"].pluck("name")).to eq(pipelines.map(&:name))
      end

      it "does not leak ids, timestamps or foreign keys" do
        keys = collect_keys(described_class.call(pipelines))

        expect(keys & %w[id created_at updated_at pipeline_id step_id action_id agent_id position]).to be_empty
      end

      it "round-trips through JSON unchanged" do
        result = described_class.call(pipelines)

        expect(JSON.parse(JSON.generate(result))).to eq(result)
      end

      it "preloads associations instead of querying per record" do
        relation = Orchestration::Pipeline.where(id: pipelines.map(&:id))
        count = 0
        counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }

        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { described_class.call(relation) }

        expect(count).to be <= 6
      end
    end

    def collect_keys(node)
      case node
      when Hash then node.keys + node.values.flat_map { |value| collect_keys(value) }
      when Array then node.flat_map { |value| collect_keys(value) }
      else []
      end
    end
  end
end
