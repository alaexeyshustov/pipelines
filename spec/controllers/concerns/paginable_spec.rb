# frozen_string_literal: true

require "rails_helper"

RSpec.describe Paginable do
  subject(:concern) { stub_class.new }

  let(:stub_class) do
    Class.new do
      include Paginable

      self.paginable_sortable          = %w[date company job_title]
      self.paginable_per_page          = [ 20, 50, 100 ]
      self.paginable_default_sort      = "date"
      self.paginable_default_direction = :desc

      attr_writer :params

      def params
        @params ||= ActionController::Parameters.new({})
      end
    end
  end

  def with_params(hash)
    concern.params = ActionController::Parameters.new(hash)
    concern
  end

  describe "#resolve_sort" do
    let(:columns) { %w[date company job_title] }

    it "returns the default when no sort param is present" do
      expect(concern.send(:resolve_sort, columns, default: "date")).to eq("date")
    end

    it "returns the column when param is in the allowlist" do
      with_params(sort: "company")
      expect(concern.send(:resolve_sort, columns, default: "date")).to eq("company")
    end

    it "returns the default when param is not in the allowlist" do
      with_params(sort: "injected; DROP TABLE users")
      expect(concern.send(:resolve_sort, columns, default: "date")).to eq("date")
    end

    it "accepts a symbol default and returns a string" do
      expect(concern.send(:resolve_sort, columns, default: :date)).to eq("date")
    end
  end

  describe "#resolve_direction" do
    it "returns :desc when no direction param is present" do
      expect(concern.send(:resolve_direction)).to eq(:desc)
    end

    it "returns :asc when param is 'asc'" do
      with_params(direction: "asc")
      expect(concern.send(:resolve_direction)).to eq(:asc)
    end

    it "returns :desc when param is 'desc'" do
      with_params(direction: "desc")
      expect(concern.send(:resolve_direction)).to eq(:desc)
    end

    it "returns :desc when param is invalid" do
      with_params(direction: "DROP TABLE")
      expect(concern.send(:resolve_direction)).to eq(:desc)
    end

    it "accepts a custom default" do
      expect(concern.send(:resolve_direction, default: :asc)).to eq(:asc)
    end
  end

  describe "#resolve_per_page" do
    let(:options) { [ 20, 50, 100 ] }

    it "returns the first option when no per_page param is present" do
      expect(concern.send(:resolve_per_page, options)).to eq(20)
    end

    it "returns the param value when it is a valid option" do
      with_params(per_page: "50")
      expect(concern.send(:resolve_per_page, options)).to eq(50)
    end

    it "returns the first option when param is not in the list" do
      with_params(per_page: "999")
      expect(concern.send(:resolve_per_page, options)).to eq(20)
    end
  end

  describe "#set_pagination_params" do
    it "sets @sort to the configured default when no param" do
      concern.send(:set_pagination_params)
      expect(concern.instance_variable_get(:@sort)).to eq("date")
    end

    it "sets @sort to the param value when it is in the allowlist" do
      with_params(sort: "company")
      concern.send(:set_pagination_params)
      expect(concern.instance_variable_get(:@sort)).to eq("company")
    end

    it "sets @direction to :desc by default" do
      concern.send(:set_pagination_params)
      expect(concern.instance_variable_get(:@direction)).to eq(:desc)
    end

    it "sets @direction to :asc when param is 'asc'" do
      with_params(direction: "asc")
      concern.send(:set_pagination_params)
      expect(concern.instance_variable_get(:@direction)).to eq(:asc)
    end

    it "sets @per_page to the first option by default" do
      concern.send(:set_pagination_params)
      expect(concern.instance_variable_get(:@per_page)).to eq(20)
    end

    it "sets @per_page from param when valid" do
      with_params(per_page: "50")
      concern.send(:set_pagination_params)
      expect(concern.instance_variable_get(:@per_page)).to eq(50)
    end
  end
end
