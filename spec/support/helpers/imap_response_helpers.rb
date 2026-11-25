# Recorded-style IMAP responses for the Yahoo adapter specs, parsed into real Net::IMAP::FetchData (no test doubles).
#
# A fixture is a stored raw message (spec/fixtures/files/imap/<name>.eml) plus its hand-recorded BODYSTRUCTURE
# (<name>.txt). Header and part bodies are sliced out of the .eml and sent as `BODY[...] {len}` literals with exact
# byte counts, so a spec compares what the code decoded against the very same bytes (`Mail.new(raw)`).
#
#   message = imap_fixture("mixed_pdf")
#   calls   = stub_imap_message(imap, message, uid: 101, validity: 77)  # answers uid_fetch/status like a server
#   calls # => [["UID", "BODYSTRUCTURE", "BODY.PEEK[HEADER]"], ["BODY.PEEK[1]<0.1048576>"]]
module ImapResponseHelpers
  FIXTURE_DIR = Rails.root.join("spec/fixtures/files/imap").freeze
  CRLF = "\r\n".freeze
  HEADERS = "From: HR Team <hr@company.com>\r\nTo: test@yahoo.com\r\nSubject: %<subject>s\r\n" \
            "Date: Mon, 1 Jan 2026 12:00:00 +0000\r\nMessage-ID: <generated@company.com>\r\nMIME-Version: 1.0\r\n".freeze

  # +raw+: the whole RFC 822 message (CRLF); +structure+: the BODYSTRUCTURE s-expression a server would send.
  Message = Data.define(:raw, :structure) do
    def header
      raw.b[/\A.*?\r\n\r\n/mn]
    end

    # The still-encoded body of the part at +path+ ("1", "2.1"), as IMAP's BODY[path] returns it.
    def part_bytes(path)
      node = Mail.new(raw)
      path.split(".").each { |index| node = node.multipart? ? node.parts.fetch(index.to_i - 1) : node }
      node.body.raw_source.b
    end

    def bodystructure
      Net::IMAP::ResponseParser.new.parse("* 1 FETCH (UID 101 BODYSTRUCTURE #{structure})\r\n").data.bodystructure
    end
  end

  def imap_fixture(name, structure: name)
    raw = File.binread(FIXTURE_DIR.join("#{name}.eml")).gsub(/\r?\n/n, CRLF.b)
    Message.new(raw: raw, structure: File.read(FIXTURE_DIR.join("#{structure}.txt")).strip)
  end

  # A single-part text/plain message with a body of any size.
  def imap_text_message(body, subject: "Generated")
    raw = format(HEADERS, subject: subject) + "Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: 7bit\r\n\r\n#{body}"
    Message.new(raw: raw.b, structure: %{("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" #{body.bytesize} #{body.count("\n") + 1} NIL NIL NIL NIL)})
  end

  # multipart/mixed with +count+ text/plain parts ("Sibling 1" ... "Sibling n"), paths "1".."n".
  def imap_siblings_message(count)
    texts = Array.new(count) { |i| "Sibling #{i + 1}" }
    raw = format(HEADERS, subject: "Siblings") + %(Content-Type: multipart/mixed; boundary="s"\r\n\r\n) +
          texts.map { |text| "--s\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n#{text}\r\n" }.join + "--s--\r\n"
    leaves = texts.map { |text| %{("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" #{text.bytesize} 1 NIL NIL NIL NIL)} }
    Message.new(raw: raw.b, structure: %{(#{leaves.join} "MIXED" ("BOUNDARY" "s") NIL NIL NIL)})
  end

  # +levels+ nested multipart/mixed; level k holds a text part "level k text" and the next multipart, so the text of
  # level k has the path "2.2. ... .1" with k elements (level 1: "1", level 2: "2.1", level 3: "2.2.1").
  def imap_nested_message(levels)
    raw = format(HEADERS, subject: "Deep") + %(Content-Type: multipart/mixed; boundary="b1"\r\n\r\n) + nested_raw(1, levels)
    Message.new(raw: raw.b, structure: nested_structure(1, levels))
  end

  # The path of the text part of nesting level +level+ in imap_nested_message.
  def nested_text_path(level)
    (([ "2" ] * (level - 1)) + [ "1" ]).join(".")
  end

  # A real FetchData for a hand-written BODYSTRUCTURE s-expression.
  def imap_bodystructure(sexp)
    Message.new(raw: "", structure: sexp).bodystructure
  end

  # Parses one untagged FETCH line (binary-safe) into a real Net::IMAP::FetchData.
  def imap_fetch_data(items, uid: 101)
    line = "* 1 FETCH (UID #{uid} ".b + items.join(" ".b) + ")\r\n".b
    Net::IMAP::ResponseParser.new.parse(line).data
  end

  def imap_literal(key, bytes)
    "#{key} {#{bytes.bytesize}}\r\n".b + bytes.b
  end

  # The FetchData a server answers to `UID FETCH uid (attrs)`; raises on an attribute the plan never sends
  # (RFC822, BODY[], BODY.PEEK[TEXT], ...), after the call has been recorded by stub_imap_message.
  # With +offset_suffix: false+ a partial range is answered as BODY[n] without the <0> origin (a server that drops it).
  def imap_fetch_response(message, attrs, uid: 101, offset_suffix: true)
    items = attrs.reject { |attr| attr == "UID" }.map { |attr| imap_fetch_item(message, attr, offset_suffix: offset_suffix) }
    imap_fetch_data(items, uid: uid)
  end

  # Answers imap.uid_fetch for +uid+ from +message+ (nil for any other UID, like a server with no such message) and,
  # with +validity+, imap.status(mailbox, ["UIDVALIDITY"]). Returns +calls+ (a list the
  # caller may pass in), which collects the requested attribute arrays in order.
  def stub_imap_message(imap, message, uid: 101, validity: nil, mailbox: "INBOX", calls: [], offset_suffix: true)
    allow(imap).to receive(:uid_fetch) do |requested_uid, attrs, *|
      calls << Array(attrs)
      requested_uid == uid ? [ imap_fetch_response(message, Array(attrs), uid: uid, offset_suffix: offset_suffix) ] : nil
    end
    allow(imap).to receive(:status).with(mailbox, [ "UIDVALIDITY" ]).and_return({ "UIDVALIDITY" => validity }) if validity
    calls
  end

  private

  def imap_fetch_item(message, attr, offset_suffix: true)
    case attr
    when "BODYSTRUCTURE" then "BODYSTRUCTURE #{message.structure}".b
    when "BODY.PEEK[HEADER]" then imap_literal("BODY[HEADER]", message.header)
    when /\ABODY\.PEEK\[(\d+(?:\.\d+)*)\](?:<0\.(\d+)>)?\z/
      path = Regexp.last_match(1)
      limit = Regexp.last_match(2)
      bytes = message.part_bytes(path)
      limit ? imap_literal("BODY[#{path}]#{'<0>' if offset_suffix}", bytes.byteslice(0, limit.to_i)) : imap_literal("BODY[#{path}]", bytes)
    else raise ArgumentError, "unexpected IMAP fetch attribute #{attr.inspect}"
    end
  end

  def nested_raw(level, levels)
    raw = "--b#{level}\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nlevel #{level} text\r\n"
    return raw + "--b#{level}--\r\n" if level == levels

    inner = %(--b#{level}\r\nContent-Type: multipart/mixed; boundary="b#{level + 1}"\r\n\r\n) + nested_raw(level + 1, levels)
    raw + inner + "--b#{level}--\r\n"
  end

  def nested_structure(level, levels)
    text = %{("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" #{"level #{level} text".bytesize} 1 NIL NIL NIL NIL)}
    children = level == levels ? text : text + nested_structure(level + 1, levels)
    %{(#{children} "MIXED" ("BOUNDARY" "b#{level}") NIL NIL NIL)}
  end
end
