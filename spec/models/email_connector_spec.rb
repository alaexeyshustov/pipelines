require "rails_helper"

RSpec.describe EmailConnector do
  def raw_configuration(connector)
    described_class.connection.select_value(
      described_class.where(id: connector.id).select(:configuration).to_sql
    )
  end

  let(:password) { "s3cret-app-password" }
  let(:yahoo) do
    described_class.create!(name: "Yahoo", provider: "yahoo", configuration: { username: "me@yahoo.com", password: })
  end

  describe "secrets at rest" do
    it "does not store the password in plaintext" do
      expect(raw_configuration(yahoo)).not_to include(password)
    end

    it "does not store the username in plaintext" do
      expect(raw_configuration(yahoo)).not_to include("me@yahoo.com")
    end

    it "does not print the password in #inspect" do
      expect(yahoo.inspect).not_to include(password)
    end

    it "round-trips the configuration through a reload" do
      expect(yahoo.reload.configuration).to eq("username" => "me@yahoo.com", "password" => password)
    end

    it "filters the configuration parameter from request logs" do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

      expect(filter.filter("configuration" => { "username" => "me@yahoo.com" })["configuration"]).to eq("[FILTERED]")
    end
  end

  describe "permitted configuration" do
    it "keeps no configuration keys for gmail" do
      connector = described_class.create!(
        name: "Gmail", provider: "gmail",
        configuration: { credentials_path: "/etc/passwd", token_path: "/tmp/t.yaml", label: "INBOX" }
      )

      expect(connector.reload.configuration).to eq({})
    end

    it "keeps only username and password for yahoo" do
      connector = described_class.create!(
        name: "Yahoo", provider: "yahoo",
        configuration: { username: "u", password: "p", host: "evil.example", port: 25, credentials_path: "/x" }
      )

      expect(connector.reload.configuration).to eq("username" => "u", "password" => "p")
    end

    it "drops stale keys when the provider changes" do
      yahoo.update!(provider: "gmail")

      expect(yahoo.reload.configuration).to eq({})
    end
  end

  describe "updating the configuration" do
    it "keeps the stored password when the submitted one is blank" do
      yahoo.update!(configuration: { "username" => "new@yahoo.com", "password" => "" })

      expect(yahoo.reload.configuration).to eq("username" => "new@yahoo.com", "password" => password)
    end

    it "keeps stored keys the update does not mention" do
      yahoo.update!(configuration: { "password" => "rotated" })

      expect(yahoo.reload.configuration).to eq("username" => "me@yahoo.com", "password" => "rotated")
    end

    it "keeps the whole configuration when a name-only update submits none" do
      yahoo.update!(name: "Renamed")

      expect(yahoo.reload.configuration).to eq("username" => "me@yahoo.com", "password" => password)
    end

    it "rejects clearing the username while a password is stored" do
      expect(yahoo.update(configuration: { "username" => "", "password" => "" })).to be(false)
      expect(yahoo.errors[:configuration]).to be_present
      expect(yahoo.reload.configuration).to eq("username" => "me@yahoo.com", "password" => password)
    end

    it "rejects a new yahoo password without a username" do
      connector = described_class.new(name: "Yahoo", provider: "yahoo", configuration: { "username" => "", "password" => "p" })

      expect(connector).not_to be_valid
    end

    it "stores no blank keys when a yahoo connector is created with empty fields" do
      connector = described_class.create!(name: "Yahoo", provider: "yahoo", configuration: { "username" => "", "password" => "" })

      expect(connector.reload.configuration).to eq({})
    end
  end
end
