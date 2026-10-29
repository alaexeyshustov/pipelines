require "rails_helper"

RSpec.describe Evaluation::DatasetCases do
  let(:dataset) { create(:evaluation_dataset) }
  let!(:first_sample) do
    create(:evaluation_dataset_sample, dataset: dataset, input: { "emails" => [ { "id" => "1" } ] },
                                       expected_tool_calls: [ { "tool_name" => "read_rows" } ])
  end
  let!(:second_sample) { create(:evaluation_dataset_sample, dataset: dataset, input: { "q" => "x" }, expected_tool_calls: nil) }

  describe ".for_sample" do
    subject(:test_case) { described_class.for_sample(first_sample) }

    it "returns a native case" do
      expect(test_case).to be_a(RubyLLM::Evaluation::Case)
    end

    it "names the case after the sample id" do
      expect(test_case.name).to eq("sample-#{first_sample.id}")
    end

    it "passes the sample input as inputs" do
      expect(test_case.inputs).to eq("emails" => [ { "id" => "1" } ])
    end

    it "carries expected tool calls in metadata" do
      expect(test_case.metadata[:expected_tool_calls]).to eq([ { "tool_name" => "read_rows" } ])
    end

    it "does not supply an expected output" do
      expect(test_case.expected_output?).to be(false)
    end

    it "defaults missing expected tool calls to an empty array" do
      expect(described_class.for_sample(second_sample).metadata[:expected_tool_calls]).to eq([])
    end
  end

  describe ".call" do
    it "returns one case per sample with unique names, in id order" do
      names = described_class.call(dataset: dataset).map(&:name)
      expect(names).to eq([ "sample-#{first_sample.id}", "sample-#{second_sample.id}" ])
    end

    it "returns an empty array for an empty dataset" do
      expect(described_class.call(dataset: create(:evaluation_dataset, name: "empty"))).to eq([])
    end
  end
end
