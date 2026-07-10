# frozen_string_literal: true

module Batchable
  extend ActiveSupport::Concern

  class_methods do
    def destroy_by_ids(ids)
      where(id: ids).destroy_all
    end
  end
end
