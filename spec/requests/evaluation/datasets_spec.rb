# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Evaluation::Datasets" do
  describe "POST /evaluation/datasets/:id/resync" do
    let!(:dataset) { create(:evaluation_dataset, agent_name: "Emails::ClassifyAgent") }

    before { allow(Evaluation::SyntheticDatasetJob).to receive(:perform_now) }

    it "runs SyntheticDatasetJob synchronously with dataset_id" do
      post resync_evaluation_dataset_path(dataset),
           params: { agent_name: "Emails::ClassifyAgent", draft_token: "tok123", count: 10 }

      expect(Evaluation::SyntheticDatasetJob).to have_received(:perform_now).with(
        hash_including(dataset_id: dataset.id, agent_name: "Emails::ClassifyAgent", count: "10")
      )
    end

    it "returns a turbo_stream response" do
      post resync_evaluation_dataset_path(dataset), params: { agent_name: "Agent", count: 5 }
      expect(response.media_type).to include("turbo-stream")
    end

    it "includes an update for the dataset count element" do
      post resync_evaluation_dataset_path(dataset), params: { agent_name: "Agent", count: 5 }
      expect(response.body).to include("dataset-count-#{dataset.id}")
    end

    context "when the job raises an error" do
      before do
        allow(Evaluation::SyntheticDatasetJob).to receive(:perform_now).and_raise(StandardError, "boom")
      end

      it "returns unprocessable_entity status" do
        post resync_evaluation_dataset_path(dataset), params: { agent_name: "Agent", count: 5 }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "renders a turbo_stream error message" do
        post resync_evaluation_dataset_path(dataset), params: { agent_name: "Agent", count: 5 }
        expect(response.body).to include("boom")
      end
    end
  end

  describe "POST /evaluation/datasets/generate" do
    before { allow(Evaluation::SyntheticDatasetJob).to receive(:perform_later) }

    it "enqueues a SyntheticDatasetJob with the given params" do
      post generate_evaluation_datasets_path,
           params: { draft_token: "tok123", agent_name: "Emails::ClassifyAgent",
                     dataset_name: "Test dataset", count: 5, hints: "Focus on edge cases" }
      expect(Evaluation::SyntheticDatasetJob).to have_received(:perform_later).with(
        hash_including(agent_name: "Emails::ClassifyAgent", draft_token: "tok123",
                       dataset_name: "Test dataset")
      )
    end

    it "returns a turbo_stream response" do
      post generate_evaluation_datasets_path, params: { agent_name: "Agent", dataset_name: "DS", count: 3 }
      expect(response.media_type).to include("turbo-stream")
    end

    context "when the job raises an error" do
      before do
        allow(Evaluation::SyntheticDatasetJob).to receive(:perform_later).and_raise(StandardError, "boom")
      end

      it "returns unprocessable_entity status" do
        post generate_evaluation_datasets_path, params: { agent_name: "Agent", dataset_name: "DS", count: 3 }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "renders a turbo_stream error message" do
        post generate_evaluation_datasets_path, params: { agent_name: "Agent", dataset_name: "DS", count: 3 }
        expect(response.body).to include("boom")
      end
    end
  end
end
