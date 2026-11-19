require "csv"

module Interviews
  class CsvExportService
    FORMULA_PREFIX = /\A[=+\-@\t\r]/

    Result = Data.define(:csv)

    def self.call(ids:) = new(ids:).call

    def initialize(ids:)
      @ids = ids
      @columns = Interview::COLUMN_NAMES.without("id")
    end

    def call
      csv = CSV.generate(headers: true) do |rows|
        rows << @columns
        scope.each { |interview| rows << @columns.map { |col| sanitize(interview.public_send(col)) } }
      end
      Result.new(csv:)
    end

    private

    def sanitize(value)
      value.is_a?(String) && value.match?(FORMULA_PREFIX) ? "'#{value}" : value
    end

    def scope
      scope = @ids.present? ? Interview.where(id: @ids) : Interview.all
      scope.order(applied_at: :desc) # : Interview::relation
    end
  end
end
