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
        criteria = Array.new
        criteria += [ "SINCE",  @after_date.strftime(IMAP_DATE_FORMAT)  ] if @after_date # steep:ignore
        criteria += [ "BEFORE", @before_date.strftime(IMAP_DATE_FORMAT) ] if @before_date # steep:ignore
        criteria << (@flagged ? "FLAGGED" : "UNFLAGGED") unless @flagged.nil?
        criteria += parse_query_criteria(@query) if @query # steep:ignore
        criteria.empty? ? [ "ALL" ] : criteria
      end

      private

      def parse_query_criteria(query)
        criteria   = Array.new
        bare_words = Array.new

        query.split(/\s+/).each { |token| parse_token(token, criteria, bare_words) }

        criteria += [ "TEXT", bare_words.join(" ") ] unless bare_words.empty?
        criteria
      end

      def parse_token(token, criteria, bare_words)
        unless parse_prefix_token(token, criteria) || parse_is_token(token, criteria)
          bare_words << token
        end
      end

      def parse_prefix_token(token, criteria)
        case token
        when /\Afrom:(.+)\z/i    then criteria.push("FROM",    $1.to_s)
        when /\Ato:(.+)\z/i      then criteria.push("TO",      $1.to_s)
        when /\Asubject:(.+)\z/i then criteria.push("SUBJECT", $1.to_s)
        when /\Aafter:(\d{4}[-\/]\d{2}[-\/]\d{2})\z/i  then push_date_criteria(criteria, "SINCE",  $1.to_s)
        when /\Abefore:(\d{4}[-\/]\d{2}[-\/]\d{2})\z/i then push_date_criteria(criteria, "BEFORE", $1.to_s)
        else return false
        end
        true
      end

      def push_date_criteria(criteria, keyword, date_str)
        criteria.push(keyword, imap_date(date_str))
      end

      def parse_is_token(token, criteria)
        case token
        when /\Ais:unread\z/i  then criteria << "UNSEEN"
        when /\Ais:read\z/i    then criteria << "SEEN"
        when /\Ais:flagged\z/i then criteria << "FLAGGED"
        else return false
        end
        true
      end

      def imap_date(date_str)
        Date.parse(date_str.tr("/", "-")).strftime(IMAP_DATE_FORMAT)
      end
    end
  end
end
