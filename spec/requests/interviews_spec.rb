# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Interviews", type: :request do
  let(:valid_params) do
    {
      interview: {
        company:   "Acme Corp",
        job_title: "Software Engineer",
        status:    "pending_reply",
        applied_at: "2026-01-10"
      }
    }
  end

  describe "GET /interviews" do
    it "returns 200 with empty state" do
      get interviews_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No interviews found")
    end

    it "lists existing records" do
      create(:interview, company: "Acme Corp", job_title: "Backend Engineer")
      get interviews_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Corp")
      expect(response.body).to include("Backend Engineer")
    end

    it "paginates when records exceed page size" do
      create_list(:interview, 21)
      get interviews_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('aria-label="Pages"')
    end
  end

  describe "GET /interviews/:id" do
    it "returns 200 and shows all fields" do
      interview = create(:interview, company: "Acme Corp", job_title: "SRE")
      get interview_path(interview)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Corp")
      expect(response.body).to include("SRE")
    end

    it "returns 404 for a missing record" do
      get interview_path(0)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /interviews/new" do
    it "returns 200 with a blank form" do
      get new_interview_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("company")
    end
  end

  describe "POST /interviews" do
    context "with valid params" do
      it "creates a record and redirects to index" do
        expect { post interviews_path, params: valid_params }
          .to change(Interview, :count).by(1)
        expect(response).to redirect_to(interviews_path)
      end
    end

    context "with invalid params" do
      it "renders new with 422" do
        post interviews_path, params: { interview: { company: "", job_title: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("company")
      end
    end
  end

  describe "GET /interviews/:id/edit" do
    it "returns 200 with the form populated" do
      interview = create(:interview, company: "Edit Me Corp")
      get edit_interview_path(interview)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit Me Corp")
    end
  end

  describe "PATCH /interviews/:id" do
    context "with valid params" do
      it "updates the record and redirects to index" do
        interview = create(:interview, company: "Old Corp")
        patch interview_path(interview), params: { interview: { company: "New Corp" } }
        expect(response).to redirect_to(interviews_path)
        expect(interview.reload.company).to eq("New Corp")
      end
    end

    context "with invalid params" do
      it "renders edit with 422" do
        interview = create(:interview)
        patch interview_path(interview), params: { interview: { company: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /interviews/:id" do
    it "destroys the record and redirects to index" do
      interview = create(:interview)
      expect { delete interview_path(interview) }
        .to change(Interview, :count).by(-1)
      expect(response).to redirect_to(interviews_path)
    end
  end
end
