module Emails
  # Plain text from an HTML body, shared by both mail adapters (and Embeddings::Text) so the tagger and the embedder
  # get text, never markup: <style>/<script>/<head> blocks are dropped, block-closing tags and <br> become line
  # breaks, the remaining tags are removed, the common entities decoded and blank lines squeezed out.
  module HtmlText
    NOISE = %r{<(style|script|head)\b.*?</\1>}mi
    ENTITIES = { "&nbsp;" => " ", "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => '"', "&#39;" => "'" }.freeze

    module_function

    def to_text(html)
      text = html.gsub(NOISE, "").gsub(%r{</(p|div|li|tr|h\d)>|<br\s*/?>}i, "\n").gsub(/<[^>]+>/, "")
      text.gsub(/&(?:nbsp|amp|lt|gt|quot|#39);/, ENTITIES).lines.map(&:strip).compact_blank.join("\n")
    end
  end
end
