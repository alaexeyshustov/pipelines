require "rails_helper"

RSpec.describe User do
  describe "email_address" do
    it "is stripped and downcased" do
      user = create(:user, email_address: "  Admin@Example.COM ")

      expect(user.email_address).to eq("admin@example.com")
    end

    it "is unique" do
      create(:user, email_address: "admin@example.com")

      expect { create(:user, email_address: "ADMIN@example.com") }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "email_address uniqueness in the database" do
    it "is enforced by a unique index" do
      create(:user, email_address: "admin@example.com")

      expect { build(:user, email_address: "admin@example.com").save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe ".upsert_login!" do
    it "creates the user" do
      user = nil

      expect { user = described_class.upsert_login!(email_address: "Admin@Example.com", password: "s3cret-passw0rd") }
        .to change(described_class, :count).by(1)

      expect(user).to have_attributes(email_address: "admin@example.com", persisted?: true)
      expect(user.authenticate("s3cret-passw0rd")).to eq(user)
    end

    it "sets a new password on the existing user, matching the email in any case" do
      existing = create(:user, email_address: "admin@example.com", password: "old-passw0rd")

      expect { described_class.upsert_login!(email_address: " ADMIN@example.com ", password: "new-passw0rd") }
        .not_to change(described_class, :count)

      expect(existing.reload.authenticate("new-passw0rd")).to eq(existing)
      expect(existing.authenticate("old-passw0rd")).to be(false)
    end

    it "raises for a blank email" do
      expect { described_class.upsert_login!(email_address: " ", password: "s3cret-passw0rd") }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "raises for a blank password when creating" do
      expect { described_class.upsert_login!(email_address: "admin@example.com", password: "") }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "raises for a blank password on an existing user and keeps the old password" do
      existing = create(:user, email_address: "admin@example.com", password: "old-passw0rd")

      expect { described_class.upsert_login!(email_address: "admin@example.com", password: "") }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(existing.reload.authenticate("old-passw0rd")).to eq(existing)
    end
  end

  describe "password" do
    it "is stored only as a digest" do
      user = create(:user, password: "s3cret-passw0rd")

      expect(user.password_digest).to be_present
      expect(user.password_digest).not_to include("s3cret-passw0rd")
    end
  end

  describe ".authenticate_by" do
    let!(:user) { create(:user, email_address: "admin@example.com", password: "s3cret-passw0rd") }

    it "returns the user for the right password" do
      expect(described_class.authenticate_by(email_address: "admin@example.com", password: "s3cret-passw0rd")).to eq(user)
    end

    it "matches the email regardless of case and padding" do
      expect(described_class.authenticate_by(email_address: " ADMIN@example.com ", password: "s3cret-passw0rd")).to eq(user)
    end

    it "returns nil for a wrong password" do
      expect(described_class.authenticate_by(email_address: "admin@example.com", password: "nope")).to be_nil
    end

    it "returns nil for an unknown email" do
      expect(described_class.authenticate_by(email_address: "nobody@example.com", password: "s3cret-passw0rd")).to be_nil
    end
  end

  describe "sessions" do
    it "has many sessions that are destroyed with the user" do
      reflection = described_class.reflect_on_association(:sessions)

      expect(reflection.macro).to eq(:has_many)
      expect(reflection.options[:dependent]).to eq(:destroy)
    end

    it "removes the user's sessions when the user is destroyed" do
      user = create(:user)
      create(:session, user:)

      expect { user.destroy }.to change(Session, :count).by(-1)
    end
  end
end
