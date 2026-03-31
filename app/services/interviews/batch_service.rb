# frozen_string_literal: true

module Interviews
  class BatchService
    Result = Data.define(:ok, :message, :csv) do
      def initialize(ok:, message: nil, csv: nil) = super
      def ok? = ok
      def csv? = !csv.nil?
    end

    STATUS_PRIORITY = %w[rejected pending_reply having_interviews offer_received].freeze

    def initialize(ids:, batch_action:)
      @ids = ids
      @batch_action = batch_action
    end

    def call
      return Result.new(ok: false, message: "No records selected.") if @ids.blank? && ids_needed?

      count = @ids&.size || 0
      case @batch_action
      when "delete"
        Interview.where(id: @ids).destroy_all
        Result.new(ok: true, message: "Deleted #{count} record(s).")
      when "export"
        Result.new(ok: true, csv: Interviews::CsvExportService.new(ids: @ids).call)
      when "merge"
        return Result.new(ok: false, message: "Select at least 2 records to merge.") if count < 2

        merge_records
        Result.new(ok: true, message: "Merged #{count} record(s) into one.")
      else
        Result.new(ok: false, message: "Unknown batch action.")
      end
    end

    private

    def merge_records
      records     = Interview.where(id: @ids).order(:applied_at)
      target      = records.first
      others      = records.where.not(id: target.id)
      dates       = collect_dates(records)
      best_status = records.map(&:status).max_by { |status| STATUS_PRIORITY.index(status) || 0 }

      target.update!(
        status:               best_status,
        first_interview_at:   dates[0],
        second_interview_at:  dates[1],
        third_interview_at:   dates[2],
        fourth_interview_at:  dates[3]
      )
      others.destroy_all
    end

    def collect_dates(records)
      records.flat_map { |rec|
        [ rec.first_interview_at, rec.second_interview_at,
          rec.third_interview_at, rec.fourth_interview_at ]
      }.compact.uniq.sort
    end

    def ids_needed?
      @batch_action != "export"
    end
  end
end
