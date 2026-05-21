# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::RunStatusBadgeComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(status: status)) }

  it_behaves_like 'a status badge component', {
    "completed" => { label: "Completed", classes: %w[bg-green-50 text-green-700] },
    "running"   => { label: "Running",   classes: %w[bg-blue-50 text-blue-700] },
    "failed"    => { label: "Failed",    classes: %w[bg-red-50 text-red-700] },
    "pending"   => { label: "Pending",   classes: %w[bg-gray-50 text-gray-700] }
  }
end
