require 'rails_helper'

RSpec.describe Orchestration::Pipeline::Validator do
  subject(:validator) { described_class.new(pipeline, index) }

  let(:pipeline) { create(:orchestration_pipeline) }
  let(:step)     { create(:orchestration_step, pipeline: pipeline, position: 1) }
  let(:index)    { Orchestration::UpstreamSchemaIndex.build(pipeline) }

  describe '.call' do
    it 'delegates to an instance and returns results' do
      create(:orchestration_step_action, step: step, position: 1, output_key: "fetch", input_mapping: nil)
      expect(described_class.call(pipeline)).to be_an(Array)
    end
  end

  describe '#call' do
    context 'with a fully-correct pipeline (no input_mapping, no schema constraints)' do
      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch", input_mapping: nil)
      end

      it 'returns one result with no errors or warnings' do
        results = validator.call
        expect(results.size).to eq(1)
        expect(results.first.errors).to be_empty
        expect(results.first.warnings).to be_empty
      end

      it 'populates step_action_id and output_key on the result' do
        result = validator.call.first
        expect(result.output_key).to eq("fetch")
        expect(result.step_action_id).to be_a(Integer)
      end
    end

    context 'with a typo in from' do
      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch",
               input_mapping: { "emails" => { "from" => "nonexistent_key" } })
      end

      it 'returns an unknown_from error with the correct code, message, and mapping_key' do
        error = validator.call.first.errors.first
        expect(error.code).to eq(:unknown_from)
        expect(error.message).to include("nonexistent_key")
        expect(error.mapping_key).to eq("emails")
      end

      it 'names the bad from reference on the error' do
        error = validator.call.first.errors.first
        expect(error.from).to eq("nonexistent_key")
      end

      it 'produces no warnings' do
        expect(validator.call.first.warnings).to be_empty
      end
    end

    context 'with a valid from but typo in path against upstream output_schema' do
      let(:upstream_agent) do
        create(:orchestration_agent,
               output_schema: {
                 "type" => "object",
                 "properties" => { "result" => { "type" => "string" } }
               })
      end
      let(:upstream_action) { create(:orchestration_action, agent: upstream_agent) }
      let(:step2) { create(:orchestration_step, pipeline: pipeline, position: 2) }

      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch",
               action: upstream_action, input_mapping: nil)
        create(:orchestration_step_action,
               step: step2, position: 1, output_key: "classify",
               input_mapping: { "data" => { "from" => "fetch", "path" => "nonexistent_path" } })
      end

      it 'returns an invalid_path error with correct code and mapping_key' do
        error = validator.call.find { |r| r.output_key == "classify" }.errors.first
        expect(error.code).to eq(:invalid_path)
        expect(error.mapping_key).to eq("data")
      end

      it 'includes the bad path and upstream output_key in the error message' do
        error = validator.call.find { |r| r.output_key == "classify" }.errors.first
        expect(error.message).to include("nonexistent_path")
        expect(error.message).to include("fetch")
      end

      it 'populates path and from on the error' do
        error = validator.call.find { |r| r.output_key == "classify" }.errors.first
        expect(error.path).to eq("nonexistent_path")
        expect(error.from).to eq("fetch")
      end

      it 'returns no errors for the upstream step' do
        fetch_result = validator.call.find { |r| r.output_key == "fetch" }
        expect(fetch_result.errors).to be_empty
      end
    end

    context 'when upstream has no output_schema' do
      let(:step2) { create(:orchestration_step, pipeline: pipeline, position: 2) }

      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch",
               input_mapping: nil)
        create(:orchestration_step_action,
               step: step2, position: 1, output_key: "classify",
               input_mapping: { "data" => { "from" => "fetch", "path" => "any.path" } })
      end

      it 'does not produce a path error when upstream has no output_schema' do
        classify_result = validator.call.find { |r| r.output_key == "classify" }
        expect(classify_result.errors).to be_empty
      end
    end

    context 'with a key collision between input_mapping and params' do
      let(:action) do
        create(:orchestration_action, params: { "key1" => "default_value" })
      end

      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch",
               action: action,
               input_mapping: { "key1" => { "from" => "_initial" } })
      end

      it 'produces no errors' do
        expect(validator.call.first.errors).to be_empty
      end

      it 'produces a param_collision warning naming the colliding key' do
        warning = validator.call.first.warnings.first
        expect(warning.code).to eq(:param_collision)
        expect(warning.message).to include("key1")
        expect(warning.mapping_key).to eq("key1")
      end
    end

    it 'does not raise on a misconfigured pipeline' do
      create(:orchestration_step_action,
             step: step, position: 1, output_key: "bad",
             input_mapping: { "x" => { "from" => "bad_ref" } })
      expect { validator.call }.not_to raise_error
    end

    context 'with a non-Hash spec value in input_mapping' do
      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch",
               input_mapping: { "key" => "plain_string_value" })
      end

      it 'does not raise' do
        expect { validator.call }.not_to raise_error
      end

      it 'returns no errors for the malformed entry' do
        expect(validator.call.first.errors).to be_empty
      end
    end

    context 'with _initial as a from reference' do
      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch",
               input_mapping: { "run_date" => { "from" => "_initial", "path" => "date" } })
      end

      it 'does not produce an unknown_from error for _initial' do
        results = validator.call
        expect(results.first.errors.none? { |e| e.code == :unknown_from }).to be true
      end
    end
  end
end
