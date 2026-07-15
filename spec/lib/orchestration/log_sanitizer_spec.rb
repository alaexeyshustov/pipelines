require "rails_helper"

RSpec.describe Orchestration::LogSanitizer do
  describe ".sanitize_string" do
    it "redacts a plain email address" do
      expect(described_class.sanitize_string("Contact us at hr@company.com for details"))
        .to eq("Contact us at [REDACTED_EMAIL] for details")
    end

    it "redacts multiple email addresses" do
      expect(described_class.sanitize_string("From: a@b.com To: c@d.org"))
        .to eq("From: [REDACTED_EMAIL] To: [REDACTED_EMAIL]")
    end

    it "redacts an api_key JSON value" do
      expect(described_class.sanitize_string('{"api_key": "sk-1234567890abcdef"}'))
        .to eq('{"api_key": "[REDACTED]"}')
    end

    it "redacts a token JSON value" do
      expect(described_class.sanitize_string('{"token": "tok_abcdef123456"}'))
        .to eq('{"token": "[REDACTED]"}')
    end

    it "redacts a secret JSON value" do
      expect(described_class.sanitize_string('{"secret": "shh-dont-tell"}'))
        .to eq('{"secret": "[REDACTED]"}')
    end

    it "redacts a password JSON value" do
      expect(described_class.sanitize_string('{"password": "hunter2"}'))
        .to eq('{"password": "[REDACTED]"}')
    end

    it "redacts an authorization JSON value" do
      expect(described_class.sanitize_string('{"authorization": "Basic abc123=="}'))
        .to eq('{"authorization": "[REDACTED]"}')
    end

    it "redacts a Bearer token" do
      expect(described_class.sanitize_string("Authorization: Bearer sk-abc123def456ghi789"))
        .to eq("Authorization: Bearer [REDACTED]")
    end

    it "redacts email, api_key, and Bearer token together in gsub order (email, then key/token, then Bearer)" do
      input = 'Contact hr@company.com. {"api_key": "sk-live-1234"} Authorization: Bearer sk-abc123def456'
      expect(described_class.sanitize_string(input)).to eq(
        'Contact [REDACTED_EMAIL]. {"api_key": "[REDACTED]"} Authorization: Bearer [REDACTED]'
      )
    end

    it "leaves a message with no sensitive content unchanged" do
      expect(described_class.sanitize_string("Just a plain message with no secrets"))
        .to eq("Just a plain message with no secrets")
    end

    it "truncates a string longer than MAX_EXCERPT_LENGTH and appends an ellipsis" do
      long_string = "x" * 510
      result = described_class.sanitize_string(long_string)

      expect(result).to end_with("...")
      expect(result.length).to eq(described_class::MAX_EXCERPT_LENGTH + 3)
      expect(result).to eq("#{'x' * described_class::MAX_EXCERPT_LENGTH}...")
    end

    it "redacts an email inside a long string before truncating" do
      long_string = ("y" * 480) + " test@example.com " + ("z" * 30)
      result = described_class.sanitize_string(long_string)

      expect(result).to start_with("y" * 480)
      expect(result).to include("[REDACTED_EMAIL]")
      expect(result).to end_with("...")
    end
  end

  describe ".sanitize_value" do
    it "redacts sensitive keys and email values across a nested hash and array" do
      nested = {
        "api_key" => "secret1",
        "nested" => { "token" => "secret2", "safe" => "value", "email" => "x@y.com" },
        "list" => [ "a@b.com", "safe" ]
      }

      expect(described_class.sanitize_value(nested)).to eq(
        "api_key" => "[REDACTED]",
        "nested" => { "token" => "[REDACTED]", "safe" => "value", "email" => "[REDACTED_EMAIL]" },
        "list" => [ "[REDACTED_EMAIL]", "safe" ]
      )
    end

    it "passes through non-string, non-collection values unchanged" do
      expect(described_class.sanitize_value(42)).to eq(42)
      expect(described_class.sanitize_value(nil)).to be_nil
      expect(described_class.sanitize_value(true)).to be(true)
    end
  end
end
