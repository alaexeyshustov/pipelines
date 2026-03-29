# frozen_string_literal: true

module ApplicationMails
  class BatchService
    Result = Data.define(:ok, :message) do
      def ok? = ok
    end

    def initialize(ids:, batch_action:)
      @ids = ids
      @batch_action = batch_action
    end

    def call
      case @batch_action
      when "delete"
        ApplicationMail.where(id: @ids).destroy_all
        Result.new(ok: true, message: "Deleted #{@ids.size} record(s).")
      when "fill"
        Records::FillJob.perform_later(@ids)
        Result.new(ok: true, message: "Fill job enqueued for #{@ids.size} record(s).")
      when "normalize"
        Records::NormalizeJob.perform_later(@ids)
        Result.new(ok: true, message: "Normalize job enqueued for #{@ids.size} record(s).")
      when "reconcile"
        Records::ReconcileJob.perform_later(@ids)
        Result.new(ok: true, message: "Reconcile job enqueued for #{@ids.size} record(s).")
      else
        Result.new(ok: false, message: "Unknown batch action.")
      end
    end
  end
end
