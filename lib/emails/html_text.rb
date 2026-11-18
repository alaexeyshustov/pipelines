module Emails
  # Plain text from an HTML body, shared by both mail adapters (and Embeddings::Text) so the tagger and the embedder
  # get text, never markup. The body is parsed with Nokogiri::HTML5 and walked: <script>/<style>/<head>/<template>
  # blocks, comments and elements hidden from the reader (hidden, aria-hidden="true", display:none,
  # visibility:hidden, zero font size) are dropped with their subtree, since hidden text is a prompt-injection
  # vector. Block elements and <br> become line breaks; blank lines are squeezed out. The walk is iterative and the
  # parser's depth limit raised, so unclosed-tag soup can't overflow the stack; a body nested deeper still yields a
  # marker instead of raising.
  module HtmlText
    SKIPPED_TAGS = %w[script style head template].freeze
    BLOCK_TAGS   = %w[p div li tr h1 h2 h3 h4 h5 h6 ul ol table section article header footer blockquote pre].freeze
    HIDDEN_STYLE = /display\s*:\s*none|visibility\s*:\s*hidden|font-size\s*:\s*0(?:\.0+)?[a-z%]*\s*(?:;|\z)/i
    MAX_TREE_DEPTH  = 4096
    TOO_DEEP_MARKER = "[HTML body nested too deeply to extract]".freeze

    module_function

    def to_text(html)
      document = Nokogiri::HTML5(html, max_tree_depth: MAX_TREE_DEPTH)
      buffer = +""
      collect(document.root&.children.to_a, buffer)
      buffer.tr(" ", " ").lines.map(&:strip).compact_blank.join("\n")
    rescue ArgumentError => error
      raise unless error.message.include?("tree depth")

      TOO_DEEP_MARKER
    end

    # Depth-first over an explicit stack; a :newline entry closes a block element.
    def collect(nodes, buffer)
      stack = nodes.reverse #: Array[Nokogiri::XML::Node | :newline]
      while (node = stack.pop)
        if node.is_a?(Symbol)
          buffer << "\n"
        elsif node.text? || node.cdata?
          buffer << node.text
        elsif node.element? && !skipped?(node)
          collect_element(node, buffer, stack)
        end
      end
    end

    def collect_element(node, buffer, stack)
      name = node.name.downcase
      return buffer << "\n" if name == "br"

      if BLOCK_TAGS.include?(name)
        buffer << "\n"
        stack.push(:newline)
      end
      node.children.reverse_each { |child| stack.push(child) }
    end

    def skipped?(node)
      SKIPPED_TAGS.include?(node.name.downcase) ||
        node.key?("hidden") ||
        node["aria-hidden"].to_s.strip.casecmp?("true") ||
        HIDDEN_STYLE.match?(node["style"].to_s)
    end
  end
end
