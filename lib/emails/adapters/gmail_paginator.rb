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
          page_size  = [ @offset - skipped, @max_results ].min
          result     = @block.call(page_size, page_token)
          break unless result
          fetched    = (result.messages || []).size
          skipped   += fetched
          page_token = result.next_page_token
          break if page_token.nil? || fetched < page_size
        end
        page_token
      end
    end
  end
end
