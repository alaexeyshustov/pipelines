# frozen_string_literal: true

require "rails_helper"

RSpec.describe Paginable do
  let(:stub_class) do
    Class.new do
      include Paginable

      self.paginable_sortable          = %w[date company job_title]
      self.paginable_per_page          = [ 20, 50, 100 ]
      self.paginable_default_sort      = "date"
      self.paginable_default_direction = :desc

      attr_reader :filters

      def params
        @params ||= ActionController::Parameters.new({})
      end

      def initialize(param_hash = {})
        @params  = ActionController::Parameters.new(param_hash)
        @filters = ApplicationController::Filters.new(
          path: "/items", q: nil, per_page: nil, page: nil, sort: nil, direction: nil
        )
        set_pagination_params
      end
    end
  end

  def build_ctrl(params = {})
    stub_class.new(params)
  end

  describe "#set_pagination_params effect on filters" do
    context "with no params" do
      subject(:ctrl) { build_ctrl }

      it "applies the configured default sort" do
        expect(ctrl.filters.sort).to eq("date")
      end

      it "applies the configured default direction" do
        expect(ctrl.filters.direction).to eq("desc")
      end

      it "uses the first per_page option as default" do
        expect(ctrl.filters.per_page).to eq("20")
      end
    end

    context "when sort param is in the allowlist" do
      subject(:ctrl) { build_ctrl(sort: "company") }

      it "uses the param value" do
        expect(ctrl.filters.sort).to eq("company")
      end
    end

    context "when sort param is not in the allowlist" do
      subject(:ctrl) { build_ctrl(sort: "injected; DROP TABLE users") }

      it "falls back to the default sort" do
        expect(ctrl.filters.sort).to eq("date")
      end
    end

    context "when sort param default is a symbol" do
      let(:symbol_default_class) do
        Class.new do
          include Paginable

          self.paginable_sortable          = %w[date]
          self.paginable_per_page          = [ 20 ]
          self.paginable_default_sort      = :date
          self.paginable_default_direction = :desc

          attr_reader :filters

          def params
            @params ||= ActionController::Parameters.new({})
          end

          def initialize
            @filters = ApplicationController::Filters.new(
              path: "/items", q: nil, per_page: nil, page: nil, sort: nil, direction: nil
            )
            set_pagination_params
          end
        end
      end

      it "coerces the default sort to a string" do
        expect(symbol_default_class.new.filters.sort).to eq("date")
      end
    end

    context "when direction param is 'asc'" do
      subject(:ctrl) { build_ctrl(direction: "asc") }

      it "sets direction to asc" do
        expect(ctrl.filters.direction).to eq("asc")
      end
    end

    context "when direction param is 'desc'" do
      subject(:ctrl) { build_ctrl(direction: "desc") }

      it "sets direction to desc" do
        expect(ctrl.filters.direction).to eq("desc")
      end
    end

    context "when direction param is invalid" do
      subject(:ctrl) { build_ctrl(direction: "DROP TABLE") }

      it "falls back to desc" do
        expect(ctrl.filters.direction).to eq("desc")
      end
    end

    context "when per_page param matches an option" do
      subject(:ctrl) { build_ctrl(per_page: "50") }

      it "uses the param value" do
        expect(ctrl.filters.per_page).to eq("50")
      end
    end

    context "when per_page param does not match any option" do
      subject(:ctrl) { build_ctrl(per_page: "999") }

      it "falls back to the first option" do
        expect(ctrl.filters.per_page).to eq("20")
      end
    end
  end
end
