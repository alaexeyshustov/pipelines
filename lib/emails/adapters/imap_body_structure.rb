module Emails
  module Adapters
    # Flattens a parsed IMAP BODYSTRUCTURE (Net::IMAP::FetchStruct#bodystructure) into its leaf parts, so a message can
    # be read part by part without downloading it (GH #304). Pure: no IO.
    class ImapBodyStructure
      MAX_DEPTH = 10
      TEXT_TYPES = %w[text/plain text/html].freeze
      ENCODINGS = %w[7bit 8bit binary base64 quoted-printable].freeze

      # One non-multipart part. +path+ is its IMAP section ("1", "2.1"), +encoding+ its transfer encoding (7bit when
      # the server sent none or an unknown one), +size+ the encoded octet count, +location+ its Content-Location.
      Leaf = Data.define(:path, :mime_type, :charset, :encoding, :size, :filename, :inline, :location)

      class Leaf
        # A body text part: text/plain or text/html that is not an attachment, as Mail#find_attachment judges it.
        def text?
          TEXT_TYPES.include?(mime_type) && filename.nil? && location.nil?
        end

        def attachment?
          !filename.nil? && !inline
        end

        # [2, 1] for "2.1": the arguments of Net::IMAP::FetchStruct#part.
        def part_numbers
          path.split(".").map(&:to_i)
        end
      end

      # The leaves of +structure+ in tree order; parts nested deeper than MAX_DEPTH are dropped and logged.
      def self.leaves(structure)
        new.leaves(structure)
      end

      def leaves(structure)
        return [] unless structure

        walk(structure, structure.multipart? ? [] : [ 1 ])
      end

      private

      def walk(node, numbers)
        if numbers.size > MAX_DEPTH
          Rails.logger.warn("IMAP BODYSTRUCTURE nested deeper than #{MAX_DEPTH} levels; part #{numbers.join('.')} and below skipped")
          return []
        end

        case node
        when Net::IMAP::BodyTypeMultipart
          node.parts.each_with_index.flat_map { |part, index| walk(part, numbers + [ index + 1 ]) }
        else
          [ leaf(node, numbers) ]
        end
      end

      def leaf(node, numbers)
        params = parameters(node.param)
        Leaf.new(
          path: numbers.join("."), mime_type: "#{node.media_type}/#{node.subtype}".downcase,
          charset: params["charset"], # : String?
          encoding: encoding(node.encoding), size: node.size, filename: filename(node, params),
          inline: inline?(node), location: node.location
        )
      end

      def inline?(node)
        node.disposition&.dsp_type.to_s.casecmp?("inline")
      end

      def encoding(value)
        name = value.to_s.downcase
        ENCODINGS.include?(name) ? name : "7bit"
      end

      # The Content-Disposition filename, else the Content-Type name; RFC 2231 and RFC 2047 encodings decoded.
      def filename(node, type_params)
        name = parameters(node.disposition&.param)["filename"] || type_params["name"] # : String?
        name && Mail::Encodings.value_decode(name) # : String
      end

      # net-imap upcases parameter keys; Mail::ParameterHash joins and decodes RFC 2231 continuations.
      def parameters(params)
        hash = Mail::ParameterHash.new
        params&.each { |key, value| hash[key.downcase] = value }
        hash
      end
    end
  end
end
