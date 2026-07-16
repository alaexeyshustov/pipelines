
# Shared example for domain-specific status badge components.
# Caller provides a mapping of { status_value => { label: String, classes: Array<String> } }
# and a subject :rendered that renders the component with `let(:status)`.
RSpec.shared_examples 'a status badge component' do |status_map|
  status_map.each do |status_val, expected|
    context "with status #{status_val.inspect}" do
      let(:status) { status_val }

      it "renders label '#{expected[:label]}'" do
        expect(rendered.css("span").text.strip).to eq(expected[:label])
      end

      it "applies correct color classes" do
        expected[:classes].each do |klass|
          expect(rendered.css("span").first["class"]).to include(klass)
        end
      end
    end
  end
end
