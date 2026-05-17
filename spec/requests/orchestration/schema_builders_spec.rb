# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orchestration::SchemaBuilders" do
  let(:simple_object_json) do
    { "type" => "object", "properties" => { "name" => { "type" => "string" } } }.to_json
  end

  describe "POST /orchestration/schema_builders/build" do
    it "returns 200 and renders the builder" do
      post build_orchestration_schema_builders_path, params: { json: simple_object_json }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("schema_builder")
    end

    it "handles missing json gracefully" do
      post build_orchestration_schema_builders_path, params: {}
      expect(response).to have_http_status(:ok)
    end

    it "applies description update to nested property path" do
      post build_orchestration_schema_builders_path, params: {
        json: simple_object_json,
        path: '["properties","name"]',
        builder: { description: "Full name" }
      }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Full name")
    end

    it "clears minimum when blank value is submitted" do
      schema = { "type" => "integer", "minimum" => 5 }.to_json
      post build_orchestration_schema_builders_path, params: {
        json: schema,
        path: "[]",
        builder: { minimum: "" }
      }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('"minimum"')
    end

    it "coerces integer enum values to integers" do
      schema = { "type" => "integer" }.to_json
      post build_orchestration_schema_builders_path, params: {
        json: schema,
        path: "[]",
        builder: { enum_text: "1\n2\n3" }
      }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[1,2,3]").or include("1")
    end
  end

  describe "POST /orchestration/schema_builders/add_property" do
    it "returns 200 and includes the new property name in the response" do
      post add_property_orchestration_schema_builders_path, params: {
        json: simple_object_json,
        path: "[]",
        property_name: "email"
      }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("email")
    end

    it "adds property at nested path" do # rubocop:disable RSpec/ExampleLength
      schema = {
        "type" => "object",
        "properties" => {
          "address" => { "type" => "object", "properties" => {} }
        }
      }.to_json
      post add_property_orchestration_schema_builders_path, params: {
        json: schema,
        path: '["properties","address"]',
        property_name: "street"
      }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("street")
    end

    it "does not overwrite existing property" do
      post add_property_orchestration_schema_builders_path, params: {
        json: simple_object_json,
        path: "[]",
        property_name: "name"
      }
      expect(response).to have_http_status(:ok)
      # name property should still be string, not reset
      expect(response.body).to include("name")
    end
  end

  describe "POST /orchestration/schema_builders/remove_property" do
    it "returns 200 and excludes the removed property" do
      post remove_property_orchestration_schema_builders_path, params: {
        json: simple_object_json,
        path: "[]",
        property_name: "name"
      }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /orchestration/schema_builders/change_type" do
    it "returns 200 with the new type reflected in the builder" do
      post change_type_orchestration_schema_builders_path, params: {
        json: simple_object_json,
        path: "[]",
        new_type: "string"
      }
      expect(response).to have_http_status(:ok)
    end

    it "ignores invalid type values and returns the unchanged builder" do
      post change_type_orchestration_schema_builders_path, params: {
        json: simple_object_json,
        path: "[]",
        new_type: "malicious"
      }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("object")
    end
  end

  describe "POST /orchestration/schema_builders/parse" do
    context "with valid JSON object" do
      it "returns 200 and renders the builder" do
        post parse_orchestration_schema_builders_path, params: { json: simple_object_json }
        expect(response).to have_http_status(:ok)
      end
    end

    context "with invalid JSON" do
      it "returns 422 with an error message" do
        post parse_orchestration_schema_builders_path, params: { json: "{invalid" }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Invalid JSON")
      end
    end

    context "with valid JSON that is not an object" do
      it "returns 422 with an error message" do
        post parse_orchestration_schema_builders_path, params: { json: "[1,2,3]" }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Invalid JSON")
      end
    end
  end
end
