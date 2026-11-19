require "rails_helper"

RSpec.describe "Evaluation::Datasets" do
  describe "POST /evaluation/datasets/:id/resync" do
    let!(:dataset) { create(:evaluation_dataset, agent_name: "Emails::ClassifyAgent") }

    it "calls DatasetSeeder with the dataset's agent_name" do
      allow(Evaluation::DatasetSeeder).to receive(:call).and_return(nil)

      post resync_evaluation_dataset_path(dataset), params: { count: 10 }

      expect(Evaluation::DatasetSeeder).to have_received(:call).with(
        agent_name: "Emails::ClassifyAgent", sample_size: 10
      )
    end

    it "returns a turbo_stream response" do
      allow(Evaluation::DatasetSeeder).to receive(:call).and_return(nil)

      post resync_evaluation_dataset_path(dataset), params: { count: 5 }
      expect(response.media_type).to include("turbo-stream")
    end

    it "includes an update for the dataset count element" do
      allow(Evaluation::DatasetSeeder).to receive(:call).and_return(nil)

      post resync_evaluation_dataset_path(dataset), params: { count: 5 }
      expect(response.body).to include("dataset-count-#{dataset.id}")
    end

    context "with more completed runs than the cap" do
      before do
        create_completed_agent_runs("Emails::ClassifyAgent", 55)
      end

      # The seeder finds or creates the dataset by agent name.
      def seeded_count = Evaluation::Dataset.find_by!(name: "Emails::ClassifyAgent").dataset_samples.count

      { "0" => 1, "-5" => 1, "abc" => 20, "" => 20, "10.5" => 20, "010" => 10, "10000" => 50 }.each do |count, expected|
        it "seeds #{expected} samples for count=#{count.inspect}" do
          post resync_evaluation_dataset_path(dataset), params: { count: count }

          expect(response).to have_http_status(:ok)
          expect(seeded_count).to eq(expected)
        end
      end

      it "seeds the default 20 when count is absent" do
        post resync_evaluation_dataset_path(dataset)

        expect(seeded_count).to eq(20)
      end
    end

    context "when DatasetSeeder raises an error" do
      before do
        allow(Evaluation::DatasetSeeder).to receive(:call).and_raise(StandardError, "boom")
      end

      it "returns unprocessable_entity status" do
        post resync_evaluation_dataset_path(dataset), params: { count: 5 }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "renders a turbo_stream error message" do
        post resync_evaluation_dataset_path(dataset), params: { count: 5 }
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

  describe "POST /evaluation/datasets/generate with structured hints" do
    include ActiveJob::TestHelper

    { "an array" => [ "x" ], "a hash" => { a: "x" } }.each do |label, hints|
      it "responds 200 and enqueues the job when hints is #{label}" do
        expect {
          post generate_evaluation_datasets_path,
               params: { draft_token: "t", agent_name: "Agent", dataset_name: "DS", count: 3, hints: hints }
        }.to have_enqueued_job(Evaluation::SyntheticDatasetJob)

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
