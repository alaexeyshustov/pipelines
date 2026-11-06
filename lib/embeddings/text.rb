module Embeddings
  # The text embedded for an Email (subject + cleaned body) or a Document (title + text). One vector per item, so
  # the input is cut at MAX_CHARS (about 8k tokens for English, German and Russian; Qwen3 accepts 32k).
  module Text
    MAX_CHARS = 16_000
    SIGNATURE_DELIMITER = /^-- ?$/

    module_function

    def for(record)
      parts = record.is_a?(Email) ? [ record.subject, email_body(record) ] : [ record.title, record.text ]
      parts.map { |part| part.to_s.strip }.compact_blank.join("\n\n")[0, MAX_CHARS].to_s
    end

    def email_body(email)
      text = email.body.presence || html_to_text(email.html_body.to_s)
      without_quotes_and_signature(text)
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
