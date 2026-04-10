# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ApplicationMails" do
  let(:valid_params) do
    {
      application_mail: {
        date:      "2026-01-15",
        provider:  "gmail",
        email_id:  "offer@acme.com",
        company:   "Acme Corp",
        job_title: "Software Engineer",
        action:    "applied"
      }
    }
  end

  describe "GET /application_mails" do
    it "returns 200 with empty state" do
      get application_mails_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No records found.")
    end

    it "lists existing records" do
      mail = create(:application_mail, company: "Acme Corp", job_title: "Engineer")
      get application_mails_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Corp")
      expect(response.body).to include("Engineer")
    end

    it "paginates when records exceed page size" do
      create_list(:application_mail, 21)
      get application_mails_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('aria-label="Pages"')
    end

    it "sorts by a valid column ascending" do
      create(:application_mail, company: "Zebra Corp")
      create(:application_mail, company: "Alpha Corp")
      get application_mails_path, params: { sort: "company", direction: "asc" }
      expect(response).to have_http_status(:ok)
      expect(response.body.index("Alpha Corp")).to be < response.body.index("Zebra Corp")
    end

    it "sorts by a valid column descending" do
      create(:application_mail, company: "Zebra Corp")
      create(:application_mail, company: "Alpha Corp")
      get application_mails_path, params: { sort: "company", direction: "desc" }
      expect(response).to have_http_status(:ok)
      expect(response.body.index("Zebra Corp")).to be < response.body.index("Alpha Corp")
    end

    it "ignores invalid sort column and defaults to date desc" do
      get application_mails_path, params: { sort: "injected", direction: "asc" }
      expect(response).to have_http_status(:ok)
    end

    it "respects per_page param" do
      create_list(:application_mail, 30)
      get application_mails_path, params: { per_page: 50 }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("50")
    end

    it "ignores invalid per_page and uses default" do
      get application_mails_path, params: { per_page: 999 }
      expect(response).to have_http_status(:ok)
    end

    it "filters by company name" do
      create(:application_mail, company: "Acme Corp",  job_title: "SRE")
      create(:application_mail, company: "Other Corp", job_title: "SRE")
      get application_mails_path, params: { q: "Acme" }
      expect(response.body).to     include("Acme Corp")
      expect(response.body).not_to include("Other Corp")
    end

    it "filters by job title" do
      create(:application_mail, company: "Acme", job_title: "Backend Engineer")
      create(:application_mail, company: "Beta", job_title: "Product Manager")
      get application_mails_path, params: { q: "Engineer" }
      expect(response.body).to     include("Backend Engineer")
      expect(response.body).not_to include("Product Manager")
    end

    it "shows all records when query is blank" do
      create(:application_mail, company: "Acme", job_title: "Backend")
      create(:application_mail, company: "Beta", job_title: "Frontend")
      get application_mails_path, params: { q: "" }
      expect(response.body).to include("Acme")
      expect(response.body).to include("Beta")
    end

    it "preserves the search query in sort column links" do
      create(:application_mail, company: "Acme Corp")
      get application_mails_path, params: { q: "Acme", sort: "company", direction: "asc" }
      expect(response.body).to include(CGI.escapeHTML(application_mails_path(sort: "company", direction: "desc", per_page: 20, q: "Acme")))
    end

    it "preserves the search query in per-page links" do
      create(:application_mail, company: "Acme Corp")
      get application_mails_path, params: { q: "Acme" }
      expect(response.body).to include(CGI.escapeHTML(application_mails_path(sort: "date", direction: "desc", per_page: 50, q: "Acme")))
    end
  end

  describe "GET /application_mails/:id" do
    it "returns 200 and shows all fields" do
      mail = create(:application_mail, company: "Acme Corp", email_id: "test@acme.com")
      get application_mail_path(mail)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Corp")
      expect(response.body).to include("test@acme.com")
    end

    it "returns 404 for a missing record" do
      get application_mail_path(0)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /application_mails/new" do
    it "returns 200 with a blank form" do
      get new_application_mail_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("email_id")
    end
  end

  describe "POST /application_mails" do
    context "with valid params" do
      it "creates a record and redirects to index" do
        expect { post application_mails_path, params: valid_params }
          .to change(ApplicationMail, :count).by(1)
        expect(response).to redirect_to(application_mails_path)
      end
    end

    context "with invalid params" do
      it "renders new with 422" do
        post application_mails_path, params: { application_mail: { date: "", provider: "", email_id: "" } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("email_id")
      end
    end
  end

  describe "GET /application_mails/:id/edit" do
    it "returns 200 with the form populated" do
      mail = create(:application_mail, company: "Edit Me Corp")
      get edit_application_mail_path(mail)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit Me Corp")
    end
  end

  describe "PATCH /application_mails/:id" do
    context "with valid params" do
      it "updates the record and redirects to index" do
        mail = create(:application_mail, company: "Old Corp")
        patch application_mail_path(mail), params: { application_mail: { company: "New Corp" } }
        expect(response).to redirect_to(application_mails_path)
        expect(mail.reload.company).to eq("New Corp")
      end
    end

    context "with invalid params" do
      it "renders edit with 422" do
        mail = create(:application_mail)
        patch application_mail_path(mail), params: { application_mail: { email_id: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /application_mails/:id" do
    it "destroys the record and redirects to index" do
      mail = create(:application_mail)
      expect { delete application_mail_path(mail) }
        .to change(ApplicationMail, :count).by(-1)
      expect(response).to redirect_to(application_mails_path)
    end
  end

  describe "POST /application_mails/batch" do
    it "redirects with alert when no ids given" do
      post batch_application_mails_path, params: { batch_action: "fill" }

      expect(response).to redirect_to(application_mails_path)
      expect(flash[:alert]).to be_present
    end

    context "when filling" do
      let(:mails) { create_list(:application_mail, 2, company: nil) }

      it "enqueues FillJob and redirects with notice" do
        allow(Records::FillJob).to receive(:perform_later)

        post batch_application_mails_path, params: { ids: mails.map(&:id), batch_action: "fill" }

        expect(Records::FillJob).to have_received(:perform_later).with(mails.map(&:id).map(&:to_s))
        expect(response).to redirect_to(application_mails_path)
        expect(flash[:notice]).to include("Fill")
      end

      it "redirects back to the referer (preserving filters) on success" do
        allow(Records::FillJob).to receive(:perform_later)
        referer = application_mails_path(q: "Acme", per_page: 50, sort: "date", direction: "asc")

        post batch_application_mails_path,
             params: { ids: mails.map(&:id), batch_action: "fill" },
             headers: { "HTTP_REFERER" => referer }

        expect(response).to redirect_to(referer)
      end
    end

    context "when deleting" do
      it "destroys selected records and redirects with notice" do
        mails = create_list(:application_mail, 3)
        ids = mails.first(2).map(&:id)

        expect { post batch_application_mails_path, params: { ids: ids, batch_action: "delete" } }
          .to change(ApplicationMail, :count).by(-2)

        expect(response).to redirect_to(application_mails_path)
        expect(flash[:notice]).to include("Deleted")
      end
    end

    context "when normalizing" do
      let(:mails) { create_list(:application_mail, 2) }

      it "enqueues NormalizeJob and redirects with notice" do
        allow(Records::NormalizeJob).to receive(:perform_later)

        post batch_application_mails_path, params: { ids: mails.map(&:id), batch_action: "normalize" }

        expect(Records::NormalizeJob).to have_received(:perform_later).with(mails.map(&:id).map(&:to_s))
        expect(response).to redirect_to(application_mails_path)
        expect(flash[:notice]).to include("Normalize")
      end
    end

    context "when reconciling" do
      let(:mails) { create_list(:application_mail, 2) }

      it "enqueues ReconcileJob and redirects with notice" do
        allow(Records::ReconcileJob).to receive(:perform_later)

        post batch_application_mails_path, params: { ids: mails.map(&:id), batch_action: "reconcile" }

        expect(Records::ReconcileJob).to have_received(:perform_later).with(mails.map(&:id).map(&:to_s))
        expect(response).to redirect_to(application_mails_path)
        expect(flash[:notice]).to include("Reconcile")
      end
    end
  end
end
