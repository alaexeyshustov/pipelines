module Embeddings
  # The text embedded for a record: its +embedding_parts+ (an Email's subject and cleaned body, a Document's title and
  # text; the models know their own parts, so this layer depends on no model) joined. One vector per item, so the
  # input is cut at MAX_CHARS (about 8k tokens for English, German and Russian; Qwen3 accepts 32k).
  module Text
    MAX_CHARS = 16_000
    SIGNATURE_DELIMITER = /^-- ?$/

    module_function

    def for(record)
      record.embedding_parts.map { |part| part.to_s.strip }.compact_blank.join("\n\n")[0, MAX_CHARS].to_s
    end

    # An email body for embedding: the plain body, else the text of the HTML one, without quoted replies and signature.
    def email_body(body, html_body)
      without_quotes_and_signature(body.presence || html_to_text(html_body.to_s))
    end

    def html_to_text(html)
      Emails::HtmlText.to_text(html)
    end

    def without_quotes_and_signature(text)
      kept = text.lines.take_while { |line| !line.chomp.match?(SIGNATURE_DELIMITER) }
      kept.reject { |line| line.start_with?(">") }.join
    end
  end
end
