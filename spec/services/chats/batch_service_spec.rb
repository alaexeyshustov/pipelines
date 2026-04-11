# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chats::BatchService do
  describe "#call" do
    let(:chats) { create_list(:chat, 2) }
    let(:ids) { chats.map(&:id) }

    context "when action is delete" do
      it "destroys the selected chats" do
        service = described_class.new(ids: ids, batch_action: "delete")
        result = service.call

        expect(result.ok?).to be true
        expect(result.message).to eq("Deleted 2 chat(s).")
        expect(Chat.where(id: ids).count).to eq(0)
      end
    end

    context "when no ids are provided" do
      it "returns failure result" do
        service = described_class.new(ids: [], batch_action: "delete")
        result = service.call

        expect(result.ok?).to be false
        expect(result.message).to eq("No chats selected.")
      end
    end

    context "when unknown action is provided" do
      it "returns failure result" do
        service = described_class.new(ids: ids, batch_action: "unknown")
        result = service.call

        expect(result.ok?).to be false
        expect(result.message).to eq("Unknown batch action.")
      end
    end
  end
end
