
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

  describe "POST /evaluation/metrics" do
    let(:valid_params) do
      {
        evaluation_metric: {
          agent_name: "Emails::ClassifyAgent",
          name: "clarity",
          description: "Output clarity",
          weight: 1.0,
          active: true
        }
      }
    end

    context "with valid params" do
      it "creates a metric" do
        expect {
          post evaluation_metrics_path, params: valid_params
        }.to change(Evaluation::Metric, :count).by(1)
      end

      it "redirects to metrics index (html)" do
        post evaluation_metrics_path, params: valid_params
        expect(response).to redirect_to(evaluation_metrics_path)
        expect(flash[:notice]).to eq("Metric created.")
      end

      it "responds with turbo_stream when requested" do
        post evaluation_metrics_path,
             params: valid_params,
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end
    end

    context "with invalid params (missing name)" do
      let(:invalid_params) { { evaluation_metric: { agent_name: "", name: "", weight: nil } } }

      it "returns 422 (html)" do
        post evaluation_metrics_path, params: invalid_params
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 422 with turbo_stream" do
        post evaluation_metrics_path,
             params: invalid_params,
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /evaluation/metrics/:id" do
    let!(:metric) { create(:evaluation_metric) }

    it "destroys the metric" do
      expect {
        delete evaluation_metric_path(metric)
      }.to change(Evaluation::Metric, :count).by(-1)
    end

    it "redirects to metrics index" do
      delete evaluation_metric_path(metric)
      expect(response).to redirect_to(evaluation_metrics_path)
      expect(flash[:notice]).to eq("Metric deleted.")
    end

    it "responds with turbo_stream remove when requested" do
      delete evaluation_metric_path(metric),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    end
  end

  describe "POST /evaluation/metrics/generate" do
    let(:suggestions) { [ { name: "clarity", description: "Output is clear", weight: 1.0 } ] }

    before do
      allow(Evaluation::MetricSuggester).to receive(:call).and_return(suggestions)
    end

    it "renders suggestions partial with the suggestions" do
      post generate_evaluation_metrics_path, params: { agent_name: "Emails::ClassifyAgent" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("clarity")
    end

    it "calls MetricSuggester with the agent_name" do
      post generate_evaluation_metrics_path, params: { agent_name: "Emails::ClassifyAgent" }
      expect(Evaluation::MetricSuggester).to have_received(:call).with(agent_name: "Emails::ClassifyAgent")
    end

    context "when MetricSuggester raises an error" do
      before do
        allow(Evaluation::MetricSuggester).to receive(:call)
          .and_raise(Evaluation::MetricSuggester::Error, "LLM unavailable")
      end

      it "returns 422 with JSON error" do
        post generate_evaluation_metrics_path, params: { agent_name: "Emails::ClassifyAgent" }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("LLM unavailable")
      end
    end
  end
end
