module Emails
  module Adapters
    class ImapSearchCriteria
      IMAP_DATE_FORMAT = "%d-%b-%Y"

      def initialize(query: nil, flagged: nil, after_date: nil, before_date: nil)
        @query       = query
        @flagged     = flagged
        @after_date  = after_date
        @before_date = before_date
      end

      def build
        criteria = [] # : Array[String]
        criteria += [ "SINCE",  @after_date.strftime(IMAP_DATE_FORMAT)  ] if @after_date
        criteria += [ "BEFORE", @before_date.strftime(IMAP_DATE_FORMAT) ] if @before_date
        criteria << (@flagged ? "FLAGGED" : "UNFLAGGED") unless @flagged.nil?
        criteria += parse_query_criteria(@query) if @query
        criteria.empty? ? [ "ALL" ] : criteria
      end

      private

      def parse_query_criteria(query)
        criteria   = [] # : Array[String]
        bare_words = [] # : Array[String]

        query.split(/\s+/).each do |token|
          case token
          when /\Afrom:(.+)\z/i    then criteria += [ "FROM",    $1 ]
          when /\Ato:(.+)\z/i      then criteria += [ "TO",      $1 ]
          when /\Asubject:(.+)\z/i then criteria += [ "SUBJECT", $1 ]
          when /\Ais:unread\z/i    then criteria << "UNSEEN"
          when /\Ais:read\z/i      then criteria << "SEEN"
          when /\Ais:flagged\z/i   then criteria << "FLAGGED"
          when /\Aafter:(\d{4}[-\/]\d{2}[-\/]\d{2})\z/i
            criteria += [ "SINCE",  imap_date($1.to_s) ]
          when /\Abefore:(\d{4}[-\/]\d{2}[-\/]\d{2})\z/i
            criteria += [ "BEFORE", imap_date($1.to_s) ]
          else
            bare_words << token
          end
        end

        criteria += [ "TEXT", bare_words.join(" ") ] unless bare_words.empty?
        criteria
      end

      def imap_date(date_str)
        Date.parse(date_str.tr("/", "-")).strftime(IMAP_DATE_FORMAT)
      end
    end
  end
end
