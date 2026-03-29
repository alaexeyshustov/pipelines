# frozen_string_literal: true

require "csv"

module Interviews
  class CsvExportService
    def initialize(ids:)
      @ids = ids
      @columns = Interview::COLUMN_NAMES.without("id")
    end

    def call
      scope = @ids.present? ? Interview.where(id: @ids) : Interview.all
      scope = scope.order(:company, :job_title)
      CSV.generate(headers: true) do |csv|
        csv << @columns
        scope.each do |interview|
          csv << @columns.map { |col| interview.public_send(col) }
        end
      end
    end
  end
end
