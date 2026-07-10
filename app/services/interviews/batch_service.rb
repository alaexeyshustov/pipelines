# frozen_string_literal: true

module Interviews
  class BatchService
    Result = Data.define(:ok, :message, :csv)
    class Result
      def initialize(ok:, message: nil, csv: nil) = super
      def ok? = ok
      def csv? = !csv.nil?
    end

    STATUS_PRIORITY = %w[rejected pending_reply having_interviews offer_received].freeze

    def self.call(ids:, batch_action:) = new(ids:, batch_action:).call

    def initialize(ids:, batch_action:)
      @ids = ids
      @batch_action = batch_action
    end

    def call
      return Result.new(ok: false, message: "No records selected.") if @ids.blank? && ids_needed?

      perform_batch_action(@ids&.size || 0)
    end

    private

    def perform_batch_action(count)
      case @batch_action
      when "delete" then delete_interviews(count)
      when "export" then export_interviews
      when "merge"  then handle_merge(count)
      else Result.new(ok: false, message: "Unknown batch action.")
      end
    end

    def delete_interviews(count)
      Interview.destroy_by_ids(@ids)
      Result.new(ok: true, message: "Deleted #{count} record(s).")
    end

    def export_interviews
      Result.new(ok: true, csv: Interviews::CsvExportService.new(ids: @ids).call)
    end

    def handle_merge(count)
      return Result.new(ok: false, message: "Select at least 2 records to merge.") if count < 2

      merge_records
      Result.new(ok: true, message: "Merged #{count} record(s) into one.")
    end

    def merge_records
      records = Interview.where(id: @ids).order(:applied_at) # : Interview::relation
      target  = records.first # : Interview
      others  = records.where.not(id: target.id) # : Interview::relation

      target.update!(**build_merge_attributes(records))
      others.destroy_all
    end

    def build_merge_attributes(records)
      dates       = collect_dates(records)
      best_status = records.map(&:status).max_by { |status| STATUS_PRIORITY.index(status) || 0 } # : String?
      {
        status:              best_status,
        first_interview_at:  dates[0],
        second_interview_at: dates[1],
        third_interview_at:  dates[2],
        fourth_interview_at: dates[3]
      }
    end

    def collect_dates(records)
      interviews = records.to_a # : Array[Interview]
      interviews.flat_map { |rec|
        [ rec.first_interview_at, rec.second_interview_at,
          rec.third_interview_at, rec.fourth_interview_at ]
      }.compact.uniq.sort
    end

    def ids_needed?
      @batch_action != "export"
    end
  end
end
