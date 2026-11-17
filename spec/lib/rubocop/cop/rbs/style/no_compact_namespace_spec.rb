require "support/rubocop_support"
require "rubocop/cop/rbs/style/no_compact_namespace"

RSpec.describe RuboCop::Cop::RBS::Style::NoCompactNamespace, :config do
  def offense_highlights(source)
    inspect_rbs_source(source).map { |o| o.location.source }
  end

  it "registers an offense for a compact class name" do
    source = <<~RBS
      module UI
        class ActionComponent::LinkComponent < ViewComponent::Base
        end
      end
    RBS

    expect(offense_highlights(source)).to contain_exactly("ActionComponent::LinkComponent")
  end

  it "registers an offense for a compact module name" do
    source = <<~RBS
      module Orchestration::Executors
      end
    RBS

    expect(offense_highlights(source)).to contain_exactly("Orchestration::Executors")
  end

  it "registers no offense for nested namespace blocks" do
    source = <<~RBS
      module UI
        class ActionComponent
          class LinkComponent < ViewComponent::Base
          end
        end
      end
    RBS

    expect(inspect_rbs_source(source)).to be_empty
  end
end
