module Emails
  module Adapters
    class GmailPaginator
      def initialize(max_results, offset, &block)
        @max_results = max_results
        @offset      = offset
        @block       = block
      end

      def messages
        page_token = skip_to_offset
        @block.call(@max_results, page_token)&.messages || []
      end

      private

      def skip_to_offset
        page_token = nil
        skipped    = 0
        while skipped < @offset
          fetched, page_token = advance_page(skipped, page_token)
          skipped += fetched
          break if page_token.nil?
        end
        page_token
      end

      def advance_page(skipped, page_token)
        page_size = [ @offset - skipped, @max_results ].min
        result    = @block.call(page_size, page_token)
        return [ 0, nil ] unless result

        fetched = (result.messages || []).size
        next_token = (fetched < page_size) ? nil : result.next_page_token
        [ fetched, next_token ]
      end
    end
  end
end
