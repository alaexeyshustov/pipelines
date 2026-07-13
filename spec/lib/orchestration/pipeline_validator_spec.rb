require 'rails_helper'

RSpec.describe Orchestration::PipelineValidator do
  subject(:validator) { described_class.new(pipeline) }

  let(:pipeline) { create(:orchestration_pipeline) }
  let(:step)     { create(:orchestration_step, pipeline: pipeline, position: 1) }

  describe '#validate' do
    context 'with a fully-correct pipeline (no input_mapping, no schema constraints)' do
      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch", input_mapping: nil)
      end

      it 'returns one result with no errors or warnings' do
        results = validator.validate
        expect(results.size).to eq(1)
        expect(results.first.errors).to be_empty
        expect(results.first.warnings).to be_empty
      end

      it 'populates step_action_id and output_key on the result' do
        result = validator.validate.first
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
        error = validator.validate.first.errors.first
        expect(error.code).to eq(:unknown_from)
        expect(error.message).to include("nonexistent_key")
        expect(error.mapping_key).to eq("emails")
      end

      it 'names the bad from reference on the error' do
        error = validator.validate.first.errors.first
        expect(error.from).to eq("nonexistent_key")
      end

      it 'produces no warnings' do
        expect(validator.validate.first.warnings).to be_empty
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
        error = validator.validate.find { |r| r.output_key == "classify" }.errors.first
        expect(error.code).to eq(:invalid_path)
        expect(error.mapping_key).to eq("data")
      end

      it 'includes the bad path and upstream output_key in the error message' do
        error = validator.validate.find { |r| r.output_key == "classify" }.errors.first
        expect(error.message).to include("nonexistent_path")
        expect(error.message).to include("fetch")
      end

      it 'populates path and from on the error' do
        error = validator.validate.find { |r| r.output_key == "classify" }.errors.first
        expect(error.path).to eq("nonexistent_path")
        expect(error.from).to eq("fetch")
      end

      it 'returns no errors for the upstream step' do
        fetch_result = validator.validate.find { |r| r.output_key == "fetch" }
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
        classify_result = validator.validate.find { |r| r.output_key == "classify" }
        expect(classify_result.errors).to be_empty
      end
    end

    context 'when the action has an input_schema with required keys all covered by input_mapping' do
      let(:agent_with_schema) do
        create(:orchestration_agent,
               input_schema: {
                 "type" => "object",
                 "properties" => { "emails" => { "type" => "array" }, "topic" => { "type" => "string" } },
                 "required" => [ "emails", "topic" ]
               })
      end
      let(:action_with_schema) { create(:orchestration_action, agent: agent_with_schema) }

      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "classify",
               action: action_with_schema,
               input_mapping: {
                 "emails" => { "from" => "_initial", "path" => "emails" },
                 "topic"  => { "from" => "_initial", "path" => "topic" }
               })
      end

      it 'produces no missing_required_input errors' do
        expect(validator.validate.first.errors).to be_empty
      end
    end

    context 'when the action has an input_schema and a required key is absent from input_mapping' do
      let(:agent_with_schema) do
        create(:orchestration_agent,
               input_schema: {
                 "type" => "object",
                 "properties" => { "emails" => { "type" => "array" }, "topic" => { "type" => "string" } },
                 "required" => [ "emails", "topic" ]
               })
      end
      let(:action_with_schema) { create(:orchestration_action, agent: agent_with_schema) }

      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "classify",
               action: action_with_schema,
               input_mapping: { "emails" => { "from" => "_initial", "path" => "emails" } })
      end

      it 'emits a missing_required_input warning (not an error)' do
        result = validator.validate.first
        warning = result.warnings.find { |w| w.code == :missing_required_input }
        expect(warning).not_to be_nil
        expect(warning).to have_attributes(message: include("topic"), mapping_key: "topic")
        expect(result.errors.none? { |e| e.code == :missing_required_input }).to be true
      end

      it 'produces no warnings for the covered required key' do
        warnings = validator.validate.first.warnings
        expect(warnings.none? { |w| w.mapping_key == "emails" }).to be true
      end
    end

    context 'when the action has an input_schema but no required keys' do
      let(:agent_with_schema) do
        create(:orchestration_agent,
               input_schema: {
                 "type" => "object",
                 "properties" => { "limit" => { "type" => "integer" } }
               })
      end
      let(:action_with_schema) { create(:orchestration_action, agent: agent_with_schema) }

      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch",
               action: action_with_schema,
               input_mapping: nil)
      end

      it 'produces no missing_required_input errors' do
        expect(validator.validate.first.errors).to be_empty
      end
    end

    context 'when the action has no input_schema' do
      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch",
               input_mapping: nil)
      end

      it 'produces no missing_required_input errors' do
        expect(validator.validate.first.errors).to be_empty
      end
    end

    it 'does not raise on a misconfigured pipeline' do
      create(:orchestration_step_action,
             step: step, position: 1, output_key: "bad",
             input_mapping: { "x" => { "from" => "bad_ref" } })
      expect { validator.validate }.not_to raise_error
    end

    context 'with a non-Hash spec value in input_mapping' do
      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch",
               input_mapping: { "key" => "plain_string_value" })
      end

      it 'does not raise' do
        expect { validator.validate }.not_to raise_error
      end

      it 'returns no errors for the malformed entry' do
        expect(validator.validate.first.errors).to be_empty
      end
    end

    context 'with _initial as a from reference' do
      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch",
               input_mapping: { "run_date" => { "from" => "_initial", "path" => "date" } })
      end

      it 'does not produce an unknown_from error for _initial' do
        results = validator.validate
        expect(results.first.errors.none? { |e| e.code == :unknown_from }).to be true
      end
    end

    context 'when a mapping entry is a literal value (not a from-reference)' do
      before do
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch",
               input_mapping: { "key" => { "value" => "literal", "from" => "nonexistent_key" } })
      end

      it 'short-circuits before from/path validation, ignoring an otherwise-invalid from' do
        errors = validator.validate.first.errors
        expect(errors.none? { |e| e.code == :unknown_from }).to be true
        expect(errors.none? { |e| e.code == :invalid_path }).to be true
      end
    end

    context 'when validating a path through nested schema nodes' do
      let(:step2) { create(:orchestration_step, pipeline: pipeline, position: 2) }
      let(:upstream_action) { create(:orchestration_action, agent: upstream_agent) }

      def classify_errors(path)
        create(:orchestration_step_action,
               step: step, position: 1, output_key: "fetch",
               action: upstream_action, input_mapping: nil)
        create(:orchestration_step_action,
               step: step2, position: 1, output_key: "classify",
               input_mapping: { "data" => { "from" => "fetch", "path" => path } })
        validator.validate.find { |r| r.output_key == "classify" }.errors
      end

      context 'through an array node whose items is a Hash schema' do
        let(:upstream_agent) do
          create(:orchestration_agent,
                 output_schema: {
                   "type" => "object",
                   "properties" => {
                     "emails" => {
                       "type" => "array",
                       "items" => {
                         "type" => "object",
                         "properties" => { "subject" => { "type" => "string" } }
                       }
                     }
                   }
                 })
        end

        it 'resolves a numeric index into the items schema with no invalid_path error' do
          expect(classify_errors("emails.10.subject").none? { |e| e.code == :invalid_path }).to be true
        end

        it 'flags a non-numeric segment against the array node as invalid_path' do
          invalid = classify_errors("emails.foo").find { |e| e.code == :invalid_path }
          expect(invalid).not_to be_nil
          expect(invalid.path).to eq("emails.foo")
        end
      end

      context 'through an array node whose items is absent' do
        let(:upstream_agent) do
          create(:orchestration_agent,
                 output_schema: {
                   "type" => "object",
                   "properties" => { "emails" => { "type" => "array" } }
                 })
        end

        it 'treats a trailing numeric index as valid (traversal ends on nil)' do
          expect(classify_errors("emails.10").none? { |e| e.code == :invalid_path }).to be true
        end

        it 'flags a deeper segment after the itemless index as invalid_path' do
          invalid = classify_errors("emails.10.subject").find { |e| e.code == :invalid_path }
          expect(invalid).not_to be_nil
          expect(invalid.path).to eq("emails.10.subject")
        end
      end

      context 'through nested object properties' do
        let(:upstream_agent) do
          create(:orchestration_agent,
                 output_schema: {
                   "type" => "object",
                   "properties" => {
                     "result" => {
                       "type" => "object",
                       "properties" => { "nested_field" => { "type" => "string" } }
                     }
                   }
                 })
        end

        it 'resolves a multi-level object path with no invalid_path error' do
          expect(classify_errors("result.nested_field").none? { |e| e.code == :invalid_path }).to be true
        end
      end
    end
  end
end
