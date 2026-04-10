# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe "Interviews" do
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
      expect(response.body).to include("No records found.")
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

    it "respects per_page param" do
      create_list(:interview, 25)
      get interviews_path, params: { per_page: 20 }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("20")
    end

    it "ignores invalid per_page and uses default" do
      get interviews_path, params: { per_page: 999 }
      expect(response).to have_http_status(:ok)
    end

    it "filters by company name" do
      create(:interview, company: "Acme Corp",  job_title: "Backend")
      create(:interview, company: "Other Corp", job_title: "Frontend")
      get interviews_path, params: { q: "Acme" }
      expect(response.body).to     include("Acme Corp")
      expect(response.body).not_to include("Other Corp")
    end

    it "filters by job title" do
      create(:interview, company: "Acme", job_title: "Backend Engineer")
      create(:interview, company: "Beta", job_title: "Product Manager")
      get interviews_path, params: { q: "Engineer" }
      expect(response.body).to     include("Backend Engineer")
      expect(response.body).not_to include("Product Manager")
    end

    it "shows all records when query is blank" do
      create(:interview, company: "Acme", job_title: "Backend")
      create(:interview, company: "Beta", job_title: "Frontend")
      get interviews_path, params: { q: "" }
      expect(response.body).to include("Acme")
      expect(response.body).to include("Beta")
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
        expect(response).to have_http_status(:unprocessable_content)
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
        expect(response).to have_http_status(:unprocessable_content)
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

  describe "POST /interviews/batch" do
    it "redirects with alert when no ids given" do
      post batch_interviews_path, params: { batch_action: "delete" }

      expect(response).to redirect_to(interviews_path)
      expect(flash[:alert]).to be_present
    end

    context "when deleting" do
      it "destroys selected records and redirects with notice" do
        interviews = create_list(:interview, 3)
        ids = interviews.first(2).map(&:id)

        expect { post batch_interviews_path, params: { ids: ids, batch_action: "delete" } }
          .to change(Interview, :count).by(-2)

        expect(response).to redirect_to(interviews_path)
        expect(flash[:notice]).to include("Deleted")
      end

      it "redirects back preserving session filters on success" do
        interview = create(:interview)

        get interviews_path(q: "Acme", per_page: 20)
        post batch_interviews_path, params: { ids: [ interview.id ], batch_action: "delete" }

        expect(response).to redirect_to(interviews_path(q: "Acme", per_page: 20))
      end
    end

    context "when exporting" do
      let(:acme_interview) { create(:interview, company: "Acme", job_title: "Backend", applied_at: "2026-01-10") }
      let(:beta_interview) { create(:interview, company: "Beta", job_title: "Frontend", applied_at: "2026-02-05") }

      before { post batch_interviews_path, params: { ids: [ acme_interview.id, beta_interview.id ], batch_action: "export" } }

      it "returns a CSV attachment response" do
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("text/csv")
        expect(response.headers["Content-Disposition"]).to include("attachment")
      end

      it "includes all selected records in the CSV body" do
        rows = CSV.parse(response.body, headers: true)
        expect(rows.size).to eq(2)
        expect(rows.map { |r| r["company"] }).to contain_exactly("Acme", "Beta")
        expect(response.headers["Content-Disposition"]).to include("interviews_")
      end
    end

    context "when exporting with no ids selected" do
      before do
        create(:interview, company: "Acme", job_title: "Backend", applied_at: "2026-01-10")
        create(:interview, company: "Beta", job_title: "Frontend", applied_at: "2026-02-05")
        post batch_interviews_path, params: { batch_action: "export" }
      end

      it "returns a CSV response" do
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("text/csv")
      end

      it "returns a CSV with all records" do
        rows = CSV.parse(response.body, headers: true)
        expect(rows.size).to eq(2)
        expect(rows.map { |r| r["company"] }).to contain_exactly("Acme", "Beta")
      end
    end

    context "when merging" do
      let(:earlier) do
        create(:interview, company: "Acme", job_title: "Engineer A",
               applied_at: "2026-01-01", status: "pending_reply",
               first_interview_at: "2026-01-10")
      end
      let(:later) do
        create(:interview, company: "Acme", job_title: "Engineer B",
               applied_at: "2026-01-05", status: "having_interviews",
               first_interview_at: "2026-01-20", second_interview_at: "2026-01-25")
      end

      it "redirects with alert when fewer than 2 ids given" do
        interview = create(:interview)

        post batch_interviews_path, params: { ids: [ interview.id ], batch_action: "merge" }

        expect(response).to redirect_to(interviews_path)
        expect(flash[:alert]).to be_present
      end

      it "deletes the duplicate and redirects with notice" do
        post batch_interviews_path, params: { ids: [ earlier.id, later.id ], batch_action: "merge" }
        expect(Interview.count).to eq(1)
        expect(response).to redirect_to(interviews_path)
        expect(flash[:notice]).to include("Merged")
      end

      it "shifts interview dates into consecutive slots" do
        post batch_interviews_path, params: { ids: [ earlier.id, later.id ], batch_action: "merge" }
        merged = earlier.reload
        expect(merged.first_interview_at.to_s).to eq("2026-01-10")
        expect(merged.second_interview_at.to_s).to eq("2026-01-20")
        expect(merged.third_interview_at.to_s).to eq("2026-01-25")
      end

      it "picks the most progressed status" do
        post batch_interviews_path, params: { ids: [ earlier.id, later.id ], batch_action: "merge" }
        expect(earlier.reload.status).to eq("having_interviews")
      end

      it "picks offer_received status over others" do
        i1 = create(:interview, company: "Acme", job_title: "Dev A",
                    applied_at: "2026-01-01", status: "rejected")
        i2 = create(:interview, company: "Acme", job_title: "Dev B",
                    applied_at: "2026-01-05", status: "offer_received")

        post batch_interviews_path, params: { ids: [ i1.id, i2.id ], batch_action: "merge" }

        expect(i1.reload.status).to eq("offer_received")
      end
    end
  end

  describe "POST /interviews/export_gist" do
    let!(:interview) { create(:interview, company: "Acme", job_title: "Backend", applied_at: "2026-01-10") }

    context "when gist_id is missing" do
      it "redirects with alert" do
        post export_gist_interviews_path, params: { gist_id: "" }
        expect(response).to redirect_to(interviews_path)
        expect(flash[:alert]).to include("Gist ID")
      end
    end

    context "when gist_id is present", vcr: { cassette_name: "interviews/gist_export/success" } do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return("fake-token")
      end

      it "redirects with notice on success" do
        post export_gist_interviews_path, params: { ids: [ interview.id ], gist_id: "abc123" }
        expect(response).to redirect_to(interviews_path)
        expect(flash[:notice]).to include("abc123")
      end
    end

    context "when gist is not found", vcr: { cassette_name: "interviews/gist_export/not_found" } do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return("fake-token")
      end

      it "redirects with alert on failure" do
        post export_gist_interviews_path, params: { ids: [ interview.id ], gist_id: "notfound" }
        expect(response).to redirect_to(interviews_path)
        expect(flash[:alert]).to include("Not Found")
      end
    end
  end
end
