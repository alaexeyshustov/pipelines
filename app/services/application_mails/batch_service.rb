# frozen_string_literal: true

module ApplicationMails
  class BatchService
    Result = Data.define(:ok, :message)
    class Result
      def ok? = ok
    end

    def self.call(ids:, batch_action:) = new(ids:, batch_action:).call

    def initialize(ids:, batch_action:)
      @ids = ids
      @batch_action = batch_action
    end

    def call
      return Result.new(ok: false, message: "No records selected.") if @ids.blank?

      dispatch(@ids.size)
    end

    private

    def dispatch(count)
      case @batch_action
      when "delete"    then delete_records(count)
      when "fill"      then enqueue_fill(count)
      when "normalize" then enqueue_normalize(count)
      when "reconcile" then enqueue_reconcile(count)
      else Result.new(ok: false, message: "Unknown batch action.")
      end
    end

    def delete_records(count)
      ApplicationMail.where(id: @ids).destroy_all
      Result.new(ok: true, message: "Deleted #{count} record(s).")
    end

    def enqueue_fill(count)
      Records::FillJob.perform_later(@ids)
      Result.new(ok: true, message: "Fill job enqueued for #{count} record(s).")
    end

    def enqueue_normalize(count)
      Records::NormalizeJob.perform_later(@ids)
      Result.new(ok: true, message: "Normalize job enqueued for #{count} record(s).")
    end

    def enqueue_reconcile(count)
      Records::ReconcileJob.perform_later(@ids)
      Result.new(ok: true, message: "Reconcile job enqueued for #{count} record(s).")
    end
  end
end
