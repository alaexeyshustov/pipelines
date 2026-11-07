module UI
  # Renders an FTS snippet: "[[hit]]" markers become <mark>; all text is escaped by ERB.
  class HighlightedSnippetComponent < ViewComponent::Base
    Segment = Data.define(:text, :hit)

    def initialize(snippet:)
      @snippet = snippet
    end

    def render?
      @snippet.present?
    end

    def segments
      @snippet.to_s.split(/(\[\[.*?\]\])/m).reject(&:empty?).map do |part|
        if part.start_with?("[[") && part.end_with?("]]")
          Segment.new(text: part[2..-3].to_s, hit: true)
        else
          Segment.new(text: part, hit: false)
        end
      end
    end
  end
end
