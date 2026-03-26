# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ApplicationMails", type: :request do
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
      expect(response.body).to include("No emails found")
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
        expect(response).to have_http_status(:unprocessable_entity)
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
        expect(response).to have_http_status(:unprocessable_entity)
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
end
