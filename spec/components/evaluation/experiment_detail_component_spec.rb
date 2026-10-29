require "rails_helper"

RSpec.describe Evaluation::ExperimentDetailComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(experiment: experiment)) }

  let(:experiment) { create(:evaluation_experiment) }

  it "renders the records evaluated count" do
    expect(rendered.text).to include("Records evaluated")
  end

  it "renders the Metrics section heading" do
    expect(rendered.text).to include("Metrics")
  end

  context "when metrics exist for the agent" do
    before { create(:evaluation_metric, agent_name: experiment.prompt.name, name: "Precision") }

    it "renders the metric name" do
      expect(rendered.text).to include("Precision")
    end
  end

  context "when dataset has samples" do
    before do
      create(:evaluation_dataset_sample, dataset: experiment.dataset, input: { "email" => "subject: Job offer from ACME" })
    end

    it "renders the Dataset Records section" do
      expect(rendered.text).to include("Dataset Records")
    end

    it "renders the record input data" do
      expect(rendered.text).to include("Job offer from ACME")
    end
  end

  context "when dataset has no samples" do
    it "does not render the Dataset Records section" do
      expect(rendered.text).not_to include("Dataset Records")
    end
  end

  context "when the prompt has system and user prompts" do
    before { experiment.prompt.update!(system_prompt: "You are an assistant", user_prompt: "Classify this email") }

    it "renders a collapsible Prompt section" do
      expect(rendered.css("details summary").map(&:text)).to include(match(/Prompt/))
    end

    it "renders the system prompt text" do
      expect(rendered.text).to include("You are an assistant")
    end
  end

  context "when the prompt has an output schema" do
    before { experiment.prompt.update!(output_schema: { "type" => "object", "properties" => { "label" => { "type" => "string" } } }) }

    it "renders a collapsible Output Schema section" do
      expect(rendered.css("details summary").map(&:text)).to include(match(/Output Schema/))
    end

    it "renders the schema as pretty JSON" do
      expect(rendered.text).to include('"type": "object"')
    end
  end

  context "when the prompt has no output schema" do
    it "does not render the Output Schema section" do
      expect(rendered.text).not_to include("Output Schema")
    end
  end

  context "when a newer experiment exists" do
    before do
      create(:evaluation_experiment, status: :pending, prompt: experiment.prompt)
    end

    it "shows the pending notification" do
      expect(rendered.text).to include("pending")
    end
  end

  describe "scores and usage" do
    subject(:rendered) { render_inline(described_class.new(experiment: experiment, usage: usage, pass_rate: 0.75, metric_pass_rates: { "precision" => 0.5 })) }

    let(:experiment) { create(:evaluation_experiment, status: :completed) }
    let(:usage) { nil }

    before do
      create(:evaluation_metric, agent_name: experiment.prompt.name, name: "precision", weight: 3.0)
      create(:evaluation_metric, agent_name: experiment.prompt.name, name: "recall", weight: 1.0)
      allow(experiment).to receive(:per_metric_averages).and_return({ "precision" => 0.8, "recall" => 0.4 })
    end

    it "shows metric averages as percentages with their pass rate" do
      expect(rendered.text).to include("80%", "40%", "50% pass")
    end

    it "shows the weighted grade and the overall pass rate" do
      expect(rendered.text).to include("Weighted grade", "70.0%", "75.0%")
    end

    it "does not render a cost block without usage" do
      expect(rendered.text).not_to include("Cost")
    end

    context "with usage" do
      let(:usage) do
        Evaluation::ExperimentUsageQuery::Usage.new(
          input_tokens: 12_000, output_tokens: 3_400, total_tokens: 15_400, cache_read_tokens: 0,
          cost: BigDecimal("0.0421"), calls: 7, models: { "gpt-5.4" => 6, "jev-latest" => 1 }
        )
      end

      it "shows cost, tokens and models used" do
        expect(rendered.text).to include("$0.0421", "12,000 in / 3,400 out", "gpt-5.4, jev-latest")
      end
    end

    context "when running" do
      let(:experiment) { create(:evaluation_experiment, status: :running, pending_samples_count: 3) }

      it "shows progress and refreshes itself" do
        expect(rendered.text).to include("3 pending")
        expect(rendered.css("meta[name='turbo-refresh-interval']")).to be_present
      end
    end
  end
end
