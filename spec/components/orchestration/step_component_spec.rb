# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::StepComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:pipeline) { build_stubbed(:orchestration_pipeline, id: 1) }
  let(:step) do
    build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, name: "My Step", position: 2, enabled: true).tap do |s|
      allow(s).to receive_messages(step_actions: [], input_mapping: nil)
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
        allow(s).to receive_messages(step_actions: [], input_mapping: nil)
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
                         action: build_stubbed(:orchestration_action, name: "Classify Agent")).tap do |s|
        allow(s).to receive(:params).and_return(nil)
      end
      build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, name: "My Step", position: 2, enabled: true).tap do |s|
        allow(s).to receive_messages(step_actions: [ sa ], input_mapping: nil)
      end
    end

    it "renders the action name" do
      expect(rendered.text).to include("Classify Agent")
    end

    it "renders a detach button for the action" do
      expect(rendered.css("form[action*='step_actions']")).to be_present
    end
  end

  context "when the step has input_mapping" do
    let(:step) do
      build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, name: "My Step", position: 2, enabled: true).tap do |s|
        allow(s).to receive_messages(step_actions: [], input_mapping: { "key" => "value" })
      end
    end

    it "renders the input mapping section" do
      expect(rendered.text).to include("Input mapping:")
      expect(rendered.css("code").text).to include("key")
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
          allow(s).to receive_messages(step_actions: [], input_mapping: nil)
        end
      end

      it "returns 'Enable'" do
        expect(component.toggle_label).to eq("Enable")
      end
    end
  end
end
