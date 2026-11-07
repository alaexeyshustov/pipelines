require "rails_helper"

RSpec.describe UI::HighlightedSnippetComponent, type: :component do
  it "wraps marked terms in <mark> and escapes everything else" do
    rendered = render_inline(described_class.new(snippet: "a <b>x</b> [[hit]] [[<i>]]"))
    expect(rendered.css("mark").map(&:text)).to eq([ "hit", "<i>" ])
    expect(rendered.css("b, i")).to be_empty
    expect(rendered.text).to include("a <b>x</b>")
  end

  it "renders nothing for a blank snippet" do
    expect(render_inline(described_class.new(snippet: nil)).to_html.strip).to be_empty
  end
end
