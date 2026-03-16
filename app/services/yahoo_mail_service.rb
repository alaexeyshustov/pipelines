require "net/imap"
require "mail"
require "date"

class YahooMailService
  IMAP_DATE_FORMAT = "%d-%b-%Y"

  def initialize(host:, port:, username:, password:)
    @host     = host
    @port     = port
    @username = username
    @password = password
    @mutex    = Mutex.new
    @current_mailbox = nil
    connect!
  end

  def list_messages(mailbox: "INBOX", max_results: 10, query: nil, flagged: nil,
                    after_date: nil, before_date: nil, offset: 0)
    with_lock do
      ensure_mailbox(mailbox)
      criteria = build_search_criteria(query: query, flagged: flagged, after_date: after_date, before_date: before_date)
      uids = @imap.uid_search(criteria).sort.reverse
      uids = uids[offset, max_results] || []
      uids.map { |uid| fetch_and_parse(uid, mailbox) }.compact
    end
  end

  def get_message(uid, mailbox: "INBOX")
    with_lock do
      ensure_mailbox(mailbox)
      fetch_and_parse(uid, mailbox)
    end
  end

  def search_messages(query, max_results: 10, mailbox: "INBOX")
    list_messages(mailbox: mailbox, max_results: max_results, query: query)
  end

  def get_folders
    with_lock do
      (@imap.list("", "*") || []).map do |mb|
        { name: mb.name, delimiter: mb.delim, attributes: Array(mb.attr).map(&:to_s) }
      end
    end
  end

  def get_unread_count(mailbox: "INBOX")
    with_lock { @imap.status(mailbox, [ "UNSEEN" ])["UNSEEN"] || 0 }
  end

  def tag_email(uid, tags:, mailbox: "INBOX", action: "add")
    with_lock do
      ensure_mailbox(mailbox)
      imap_action = action == "remove" ? "-FLAGS" : "+FLAGS"
      imap_flags  = tags.map { |tag| tag.start_with?("\\") ? tag[1..].to_sym : tag }
      @imap.uid_store(uid, imap_action, imap_flags)
      { uid: uid, action: action, tags: tags, mailbox: mailbox }
    end
  end

  def disconnect
    return unless @imap

    @imap.logout rescue nil
    @imap.disconnect rescue nil
  rescue StandardError
    # ignore errors during teardown
  ensure
    @imap = nil
  end

  private

  def connect!
    @imap = Net::IMAP.new(@host, port: @port, ssl: true)
    @imap.login(@username, @password)
    @current_mailbox = nil
  end

  def ensure_mailbox(mailbox)
    return if @current_mailbox == mailbox

    @imap.select(mailbox)
    @current_mailbox = mailbox
  end

  def with_reconnect(&block)
    block.call
  rescue Net::IMAP::ByeResponseError, IOError, Errno::ECONNRESET, Errno::EPIPE => e
    $stderr.puts "IMAP connection lost (#{e.class}: #{e.message}), reconnecting..."
    connect!
    block.call
  end

  def with_lock(&block)
    @mutex.synchronize { with_reconnect(&block) }
  end

  def fetch_and_parse(uid, mailbox)
    data = @imap.uid_fetch(uid, %w[RFC822 FLAGS UID])
    return nil if data.nil? || data.empty?

    attrs = data.first.attr
    raw   = attrs["RFC822"]
    return nil if raw.nil? || raw.empty?

    mail = Mail.new(raw)
    body = extract_body(mail)

    {
      id:      uid,
      subject: decode_header(mail.subject) || "(No Subject)",
      from:    Array(mail.from).join(", ").then { |v| v.empty? ? "Unknown" : v },
      to:      Array(mail.to).join(", ").then   { |v| v.empty? ? "Unknown" : v },
      date:    mail.date&.to_s || "Unknown",
      snippet: body[0, 200],
      body:    body,
      folders: [ mailbox ]
    }
  rescue StandardError => e
    $stderr.puts "Warning: failed to parse message UID #{uid}: #{e.message}"
    nil
  end

  def extract_body(mail)
    if mail.multipart?
      plain = mail.parts.find { |p| p.mime_type == "text/plain" }
      return decode_part(plain) if plain

      html = mail.parts.find { |p| p.mime_type == "text/html" }
      return strip_html(decode_part(html)) if html

      mail.parts.filter_map { |p| extract_body(p) }.reject(&:empty?).join("\n\n")
    elsif mail.mime_type == "text/html"
      strip_html(decode_part(mail))
    else
      decode_part(mail)
    end
  end

  def decode_part(part)
    return "" unless part

    body = part.respond_to?(:decoded) ? part.decoded : part.body.decoded
    body.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?").strip
  rescue StandardError
    ""
  end

  def strip_html(html)
    html.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
  end

  def decode_header(value)
    return nil if value.nil?

    value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
  rescue StandardError
    value.to_s
  end

  def build_search_criteria(query: nil, flagged: nil, after_date: nil, before_date: nil)
    criteria = []
    criteria += [ "SINCE",  after_date.strftime(IMAP_DATE_FORMAT)  ] if after_date
    criteria += [ "BEFORE", before_date.strftime(IMAP_DATE_FORMAT) ] if before_date
    criteria << (flagged ? "FLAGGED" : "UNFLAGGED") unless flagged.nil?
    criteria += parse_query_criteria(query) if query
    criteria.empty? ? [ "ALL" ] : criteria
  end

  def parse_query_criteria(query)
    criteria   = []
    bare_words = []

    query.split(/\s+/).each do |token|
      case token
      when /\Afrom:(.+)\z/i    then criteria += [ "FROM",    $1 ]
      when /\Ato:(.+)\z/i      then criteria += [ "TO",      $1 ]
      when /\Asubject:(.+)\z/i then criteria += [ "SUBJECT", $1 ]
      when /\Ais:unread\z/i    then criteria << "UNSEEN"
      when /\Ais:read\z/i      then criteria << "SEEN"
      when /\Ais:flagged\z/i   then criteria << "FLAGGED"
      when /\Aafter:(\d{4}[-\/]\d{2}[-\/]\d{2})\z/i
        criteria += [ "SINCE",  Date.parse($1.tr("/", "-")).strftime(IMAP_DATE_FORMAT) ]
      when /\Abefore:(\d{4}[-\/]\d{2}[-\/]\d{2})\z/i
        criteria += [ "BEFORE", Date.parse($1.tr("/", "-")).strftime(IMAP_DATE_FORMAT) ]
      else
        bare_words << token
      end
    end

    criteria += [ "TEXT", bare_words.join(" ") ] unless bare_words.empty?
    criteria
  end
end
