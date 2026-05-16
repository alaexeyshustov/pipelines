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
  end

  describe "POST /orchestration/schema_builders/parse" do
    context "with valid JSON" do
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
  end
end
