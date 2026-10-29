require "rails_helper"

RSpec.describe Evaluation::MetricDefinitionFieldsComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(kind: "choice", minimum: 0.5, levels: levels)) }

  let(:levels) { { "good" => { "description" => "Fully correct", "value" => 1.0 }, "bad" => { "description" => "Wrong", "value" => 0.0 } } }

  it "preselects the kind and fills the minimum" do
    expect(rendered.css("select option[selected]").map { |o| o.attr("value") }).to eq([ "choice" ])
    expect(rendered.css("input[name='evaluation_metric[minimum]']").first["value"]).to eq("0.5")
  end

  it "dumps levels as editable text" do
    expect(rendered.css("textarea").text.strip).to eq("good | 1.0 | Fully correct\nbad | 0.0 | Wrong")
  end
end
