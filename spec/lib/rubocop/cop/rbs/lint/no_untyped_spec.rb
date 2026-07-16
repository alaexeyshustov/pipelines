
require "support/rubocop_support"
require "rubocop/cop/rbs/lint/no_untyped"

RSpec.describe RuboCop::Cop::RBS::Lint::NoUntyped, :config do
  def offense_messages(source)
    inspect_rbs_source(source).map(&:message)
  end

  def offense_highlights(source)
    inspect_rbs_source(source).map { |o| o.location.source }
  end

  context "when untyped is the return type" do
    it "registers an offense" do
      source = <<~RBS
        class Foo
          def fetch: () -> untyped
        end
      RBS

      expect(offense_messages(source)).to contain_exactly(described_class::MSG)
      expect(offense_highlights(source)).to contain_exactly("untyped")
    end
  end

  context "when untyped is a positional parameter" do
    it "registers an offense" do
      source = <<~RBS
        class Foo
          def store: (untyped value) -> void
        end
      RBS

      expect(offense_messages(source)).to contain_exactly(described_class::MSG)
      expect(offense_highlights(source)).to contain_exactly("untyped")
    end
  end

  context "when untyped is nested inside a generic type" do
    it "registers an offense" do
      source = <<~RBS
        class Foo
          def ids: () -> Array[untyped]
        end
      RBS

      expect(offense_messages(source)).to contain_exactly(described_class::MSG)
      expect(offense_highlights(source)).to contain_exactly("untyped")
    end
  end

  context "when untyped appears multiple times in the same method" do
    it "registers one offense per occurrence" do
      source = <<~RBS
        class Foo
          def convert: (untyped input) -> untyped
        end
      RBS

      expect(offense_messages(source)).to contain_exactly(described_class::MSG, described_class::MSG)
      expect(offense_highlights(source)).to contain_exactly("untyped", "untyped")
    end
  end

  context "when untyped is in a constant declaration" do
    it "registers an offense" do
      source = "MAPPING: Hash[String, untyped]\n"

      expect(offense_messages(source)).to contain_exactly(described_class::MSG)
      expect(offense_highlights(source)).to contain_exactly("untyped")
    end
  end

  context "when untyped is in an attribute declaration" do
    it "registers an offense" do
      source = <<~RBS
        class Foo
          attr_reader data: untyped
        end
      RBS

      expect(offense_messages(source)).to contain_exactly(described_class::MSG)
      expect(offense_highlights(source)).to contain_exactly("untyped")
    end
  end

  context "when all types are concrete" do
    it "registers no offense" do
      source = <<~RBS
        class Foo
          def fetch: () -> String
          def store: (Integer id, String value) -> void
          def ids: () -> Array[Integer]
          attr_reader name: String
        end
      RBS

      expect(inspect_rbs_source(source)).to be_empty
    end
  end
end
