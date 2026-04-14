# frozen_string_literal: true

module Chats
  class BatchService
    Result = Data.define(:ok, :message)
    class Result
      def initialize(ok:, message: nil) = super
      def ok? = ok
    end

    def self.call(ids:, batch_action:)
      new(ids:, batch_action:).call
    end

    def initialize(ids:, batch_action:)
      @ids = ids
      @batch_action = batch_action
    end

    def call
      return Result.new(ok: false, message: "No chats selected.") if @ids.blank?

      case @batch_action
      when "delete"
        Chat.where(id: @ids).destroy_all
        Result.new(ok: true, message: "Deleted #{@ids.size} chat(s).")
      else
        Result.new(ok: false, message: "Unknown batch action.")
      end
    end
  end
end
