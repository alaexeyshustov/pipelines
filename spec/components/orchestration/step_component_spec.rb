# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::StepComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:pipeline) { build_stubbed(:orchestration_pipeline, id: 1) }
  let(:step) do
    build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, name: "My Step", position: 2, enabled: true).tap do |s|
      allow(s).to receive_messages(step_actions: [],)
    end
  end
  let(:actions) { build_stubbed_list(:orchestration_action, 2) }
  let(:iteration) { OpenStruct.new(first?: false, last?: false) }
  let(:component) { described_class.new(step: step, step_counter: 1, step_iteration: iteration, pipeline: pipeline, actions: actions) }

  it "renders the step position badge" do
    expect(rendered.css("span").text).to include("2")
  end

  it "renders the step name" do
    expect(rendered.text).to include("My Step")
  end

  it "renders the move-up button when not first" do
    expect(rendered.css("form[action*='move_up']")).to be_present
  end

  it "renders the move-down button when not last" do
    expect(rendered.css("form[action*='move_down']")).to be_present
  end

  it "renders the toggle button with 'Disable' label for an enabled step" do
    toggle_form = rendered.css("form[action*='toggle']").first
    expect(toggle_form).to be_present
    expect(toggle_form.text).to include("Disable")
  end

  it "renders the attach action form" do
    expect(rendered.css("form[action*='step_actions']")).to be_present
  end

  it "renders all available actions in the select" do
    actions.each do |action|
      expect(rendered.css("select option[value='#{action.id}']")).to be_present
    end
  end

  context "when the step is the first in the collection" do
    let(:iteration) { OpenStruct.new(first?: true, last?: false) }

    it "does not render the move-up button" do
      expect(rendered.css("form[action*='move_up']")).to be_empty
    end

    it "still renders the move-down button" do
      expect(rendered.css("form[action*='move_down']")).to be_present
    end
  end

  context "when the step is the last in the collection" do
    let(:iteration) { OpenStruct.new(first?: false, last?: true) }

    it "does not render the move-down button" do
      expect(rendered.css("form[action*='move_down']")).to be_empty
    end

    it "still renders the move-up button" do
      expect(rendered.css("form[action*='move_up']")).to be_present
    end
  end

  context "when the step is disabled" do
    let(:step) do
      build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, name: "My Step", position: 2, enabled: false).tap do |s|
        allow(s).to receive_messages(step_actions: [],)
      end
    end

    it "renders a disabled badge" do
      expect(rendered.text).to include("disabled")
    end

    it "renders the step name with muted color" do
      p_tag = rendered.css("p").first
      expect(p_tag["class"]).to include("text-gray-400")
    end

    it "renders the toggle button with 'Enable' label" do
      toggle_form = rendered.css("form[action*='toggle']").first
      expect(toggle_form.text).to include("Enable")
    end
  end

  context "when the step has step_actions" do
    let(:step) do
      sa = build_stubbed(:orchestration_step_action,
                         action: build_stubbed(:orchestration_action, name: "Classify Agent"))
      build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, name: "My Step", position: 2, enabled: true).tap do |s|
        allow(s).to receive_messages(step_actions: [ sa ],)
      end
    end

    it "renders the action name" do
      expect(rendered.text).to include("Classify Agent")
    end

    it "renders a detach button for the action" do
      expect(rendered.css("form[action*='step_actions']")).to be_present
    end
  end

  describe "#move_up?" do
    it "returns false when first" do
      allow(iteration).to receive(:first?).and_return(true)
      expect(component.move_up?).to be(false)
    end

    it "returns true when not first" do
      allow(iteration).to receive(:first?).and_return(false)
      expect(component.move_up?).to be(true)
    end
  end

  describe "#move_down?" do
    it "returns false when last" do
      allow(iteration).to receive(:last?).and_return(true)
      expect(component.move_down?).to be(false)
    end

    it "returns true when not last" do
      allow(iteration).to receive(:last?).and_return(false)
      expect(component.move_down?).to be(true)
    end
  end

  describe "#toggle_label" do
    it "returns 'Disable' for an enabled step" do
      expect(component.toggle_label).to eq("Disable")
    end

    context "when step is disabled" do
      let(:step) do
        build_stubbed(:orchestration_step, enabled: false, id: 10, pipeline: pipeline).tap do |s|
          allow(s).to receive_messages(step_actions: [],)
        end
      end

      it "returns 'Enable'" do
        expect(component.toggle_label).to eq("Enable")
      end
    end
  end

  context "when the step has a step_action and upstream_schemas are provided" do
    let(:component) do
      sa = build_stubbed(:orchestration_step_action,
                         id: 99, output_key: "my_action",
                         input_mapping: { "email" => { "from" => "_initial", "path" => nil } },
                         action: build_stubbed(:orchestration_action, name: "My Action"))
      the_step = build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, name: "My Step", position: 2, enabled: true).tap do |s|
        allow(s).to receive_messages(step_actions: [ sa ])
      end
      described_class.new(
        step: the_step, step_counter: 1, step_iteration: iteration,
        pipeline: pipeline, actions: actions,
        upstream_schemas_per_step: { 10 => { "_initial" => nil, "prior_action" => nil } },
        validator_results_per_step: {}
      )
    end

    it "renders from select with _initial option" do
      expect(rendered.css("select[data-testid='from-select'] option[value='_initial']")).to be_present
    end

    it "renders from select with upstream output_key option" do
      expect(rendered.css("select[data-testid='from-select'] option[value='prior_action']")).to be_present
    end

    it "excludes the step_action's own output_key from from select" do
      option_values = rendered.css("select[data-testid='from-select'] option").pluck("value")
      expect(option_values).not_to include("my_action")
    end
  end

  context "when the upstream action has an output_schema with properties" do
    let(:component) do
      sa = build_stubbed(:orchestration_step_action,
                         id: 99, output_key: "my_action",
                         input_mapping: { "email" => { "from" => "prior_action", "path" => nil } },
                         action: build_stubbed(:orchestration_action, name: "My Action"))
      the_step = build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, name: "My Step", position: 2, enabled: true).tap do |s|
        allow(s).to receive_messages(step_actions: [ sa ])
      end
      upstream_schema = { "type" => "object", "properties" => { "email" => { "type" => "string" }, "name" => { "type" => "string" } } }
      described_class.new(
        step: the_step, step_counter: 1, step_iteration: iteration,
        pipeline: pipeline, actions: actions,
        upstream_schemas_per_step: { 10 => { "_initial" => nil, "prior_action" => upstream_schema } },
        validator_results_per_step: {}
      )
    end

    it "renders path as a select with schema property names as options" do
      select = rendered.css("select[data-testid='path-select']").first
      expect(select).to be_present
      option_values = select.css("option").pluck("value")
      expect(option_values).to include("email", "name")
    end
  end

  context "when the upstream action has no output_schema" do
    let(:component) do
      sa = build_stubbed(:orchestration_step_action,
                         id: 99, output_key: "my_action",
                         input_mapping: { "email" => { "from" => "_initial", "path" => nil } },
                         action: build_stubbed(:orchestration_action, name: "My Action"))
      the_step = build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, name: "My Step", position: 2, enabled: true).tap do |s|
        allow(s).to receive_messages(step_actions: [ sa ])
      end
      described_class.new(
        step: the_step, step_counter: 1, step_iteration: iteration,
        pipeline: pipeline, actions: actions,
        upstream_schemas_per_step: { 10 => { "_initial" => nil } },
        validator_results_per_step: {}
      )
    end

    it "renders path as a text input" do
      expect(rendered.css("input[data-testid='path-text']")).to be_present
    end

    it "does not render a path select" do
      expect(rendered.css("select[data-testid='path-select']")).to be_empty
    end
  end

  context "when the validator reports no errors for this step" do
    let(:component) do
      sa = build_stubbed(:orchestration_step_action,
                         id: 99, output_key: "my_action",
                         input_mapping: {},
                         action: build_stubbed(:orchestration_action, name: "My Action"))
      the_step = build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, name: "My Step", position: 2, enabled: true).tap do |s|
        allow(s).to receive_messages(step_actions: [ sa ])
      end
      described_class.new(
        step: the_step, step_counter: 1, step_iteration: iteration,
        pipeline: pipeline, actions: actions,
        upstream_schemas_per_step: { 10 => { "_initial" => nil } },
        validator_results_per_step: { 10 => [] }
      )
    end

    it "renders a green validity badge" do
      badge = rendered.css("[data-testid='validity-badge']").first
      expect(badge).to be_present
      expect(badge["class"]).to include("green")
    end
  end

  context "when the validator reports errors for this step" do
    let(:error_message) { "input_mapping key \"email\" references unknown output key \"missing\"" }
    let(:component) do
      issue = Orchestration::PipelineValidator::Issue.new(
        code: :unknown_from, message: error_message,
        mapping_key: "email", from: "missing", path: nil
      )
      result = Orchestration::PipelineValidator::StepResult.new(
        step_action_id: 99, output_key: "my_action",
        errors: [ issue ], warnings: []
      )
      sa = build_stubbed(:orchestration_step_action,
                         id: 99, output_key: "my_action",
                         input_mapping: {},
                         action: build_stubbed(:orchestration_action, name: "My Action"))
      the_step = build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, name: "My Step", position: 2, enabled: true).tap do |s|
        allow(s).to receive_messages(step_actions: [ sa ])
      end
      described_class.new(
        step: the_step, step_counter: 1, step_iteration: iteration,
        pipeline: pipeline, actions: actions,
        upstream_schemas_per_step: { 10 => { "_initial" => nil } },
        validator_results_per_step: { 10 => [ result ] }
      )
    end

    it "renders a red validity badge" do
      badge = rendered.css("[data-testid='validity-badge']").first
      expect(badge).to be_present
      expect(badge["class"]).to include("red")
    end

    it "renders the error message" do
      expect(rendered.text).to include(error_message)
    end
  end
end
