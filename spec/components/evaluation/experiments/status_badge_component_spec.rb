require "rails_helper"

RSpec.describe Evaluation::Experiments::StatusBadgeComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(experiment: experiment, with_src: false)) }

  {
    pending: [ "bg-yellow-50", true ], running: [ "bg-blue-50", true ],
    completed: [ "bg-green-50", false ], failed: [ "bg-red-50", false ]
  }.each do |status, (css, polling)|
    context "when #{status}" do
      let(:experiment) { build(:evaluation_experiment, status: status) }

      it "renders the label with its colour#{polling ? ' and polls' : ' and stops polling'}" do
        expect(rendered.css("span.#{css}").text).to include(status.to_s)
        expect(rendered.css("turbo-frame[refresh='interval']").any?).to eq(polling)
      end
    end
  end

  context "with a source" do
    subject(:rendered) { render_inline(described_class.new(experiment: experiment)) }

    let(:experiment) { create(:evaluation_experiment, status: :running) }

    it "points the frame at the status endpoint and polls every 3 seconds" do
      frame = rendered.at_css("turbo-frame#experiment-status")
      expect(frame["src"]).to eq("/evaluation/experiments/#{experiment.id}/status_frame")
      expect(frame["data-turbo-refresh-interval"]).to eq("3000")
    end
  end
end
