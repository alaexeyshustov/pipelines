# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Evaluation::Metrics" do
  describe "GET /evaluation/metrics" do
    it "returns 200 with empty state" do
      get evaluation_metrics_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Metrics")
    end

    it "lists existing metrics" do
      metric = create(:evaluation_metric)
      get evaluation_metrics_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(metric.name)
    end
  end

  describe "GET /evaluation/metrics/:id/edit" do
    it "returns 200 with edit form" do
      metric = create(:evaluation_metric)
      get edit_evaluation_metric_path(metric)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(metric.name)
    end
  end

  describe "PATCH /evaluation/metrics/:id" do
    it "redirects to index on success" do
      metric = create(:evaluation_metric)
      patch evaluation_metric_path(metric), params: { evaluation_metric: { weight: 2.0 } }
      expect(response).to redirect_to(evaluation_metrics_path)
      expect(flash[:notice]).to eq("Metric updated.")
    end

    it "persists updated attributes" do
      metric = create(:evaluation_metric)
      patch evaluation_metric_path(metric), params: { evaluation_metric: { weight: 2.0, active: false } }
      expect(metric.reload.weight).to eq(2.0)
      expect(metric.reload.active).to be(false)
    end

    it "returns 422 with invalid params" do
      metric = create(:evaluation_metric)
      patch evaluation_metric_path(metric), params: {
        evaluation_metric: { weight: nil }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
