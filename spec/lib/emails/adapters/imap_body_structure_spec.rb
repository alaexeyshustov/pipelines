require "rails_helper"

RSpec.describe Emails::Adapters::ImapBodyStructure do
  include ImapResponseHelpers

  def leaves_of(message) = described_class.leaves(message.bodystructure)

  def leaf(path, leaves) = leaves.find { |candidate| candidate.path == path }

  describe ".leaves" do
    it "treats a single-part message as one leaf with the path 1" do
      leaves = leaves_of(imap_fixture("plain"))

      expect(leaves.map(&:path)).to eq([ "1" ])
      expect(leaves.first).to have_attributes(
        mime_type: "text/plain", charset: a_string_matching(/\Aus-ascii\z/i), encoding: a_string_matching(/\A7bit\z/i),
        size: be_positive, filename: nil, inline: false
      )
    end

    it "lists the leaves of a multipart message in tree order" do
      expect(leaves_of(imap_fixture("alternative")).map(&:path)).to eq(%w[1 2])
    end

    it "numbers nested leaves like IMAP part paths" do
      leaves = leaves_of(imap_fixture("nested"))

      expect(leaves.map { |l| [ l.path, l.mime_type ] }).to eq(
        [ [ "1.1.1", "text/plain" ], [ "1.1.2", "text/html" ], [ "1.2", "image/png" ], [ "2", "application/pdf" ] ]
      )
    end

    it "gives the numeric path elements as part_numbers" do
      leaves = leaves_of(imap_fixture("nested"))

      expect(leaves.map(&:part_numbers)).to eq([ [ 1, 1, 1 ], [ 1, 1, 2 ], [ 1, 2 ], [ 2 ] ])
      expect(described_class.leaves(imap_bodystructure(%{("TEXT" "PLAIN" NIL NIL NIL "7BIT" 1 1 NIL NIL NIL NIL)})).first.part_numbers).to eq([ 1 ])
    end

    it "downcases the media type and reads the charset, encoding and declared size of a part" do
      leaves = leaves_of(imap_fixture("qp_latin1"))

      expect(leaves.sole).to have_attributes(
        mime_type: "text/plain", charset: a_string_matching(/\Aiso-8859-1\z/i), encoding: a_string_matching(/\Aquoted-printable\z/i)
      )
      expect(leaves.sole.size).to eq(imap_fixture("qp_latin1").bodystructure.size)
    end

    it "keeps a message/rfc822 part as a leaf and does not look inside it" do
      leaves = leaves_of(imap_fixture("rfc822"))

      expect(leaves.map { |l| [ l.path, l.mime_type ] }).to eq([ [ "1", "text/plain" ], [ "2", "message/rfc822" ] ])
    end

    it "treats a nil or unknown transfer encoding as 7bit" do
      nil_encoding = Net::IMAP::BodyTypeText.new("TEXT", "PLAIN", { "CHARSET" => "UTF-8" }, nil, nil, nil, 5, 1, nil, nil, nil, nil, nil)
      unknown = imap_bodystructure(%{("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "X-FOO" 5 1 NIL NIL NIL NIL)})

      expect(described_class.leaves(nil_encoding).sole.encoding).to match(/\A7bit\z/i)
      expect(described_class.leaves(unknown).sole.encoding).to match(/\A7bit\z/i)
    end

    it "downcases uppercase parameter keys and decodes an RFC 2231 and an RFC 2047 filename" do
      filenames = leaves_of(imap_fixture("encoded_filenames")).filter_map(&:filename)

      expect(filenames).to eq([ "Lebenslauf Müller.pdf", "Zeugnis Grüße.pdf", "CV Иван.pdf" ])
    end

    it "reads the filename from the Content-Type name when the disposition has none" do
      pdf = imap_bodystructure(%{("APPLICATION" "PDF" ("NAME" "cv.pdf") NIL NIL "BASE64" 10 NIL NIL NIL NIL)})

      expect(described_class.leaves(pdf).sole).to have_attributes(filename: "cv.pdf", attachment?: true)
    end

    it "marks an inline part and does not call it an attachment even with a filename" do
      logo = leaf("2", leaves_of(imap_fixture("inline_image")))

      expect(logo).to have_attributes(inline: true, filename: "logo.png", attachment?: false, text?: false)
    end

    it "does not descend deeper than 10 levels and still returns the shallower leaves" do
      allow(Rails.logger).to receive(:warn)

      leaves = leaves_of(imap_nested_message(12))
      paths = leaves.map(&:path)

      expect(paths).to include(nested_text_path(1), nested_text_path(5), nested_text_path(9))
      expect(paths).not_to include(nested_text_path(11), nested_text_path(12))
      expect(paths.map { |path| path.split(".").size }.max).to be <= 10
    end

    it "logs a warning for the subtree it drops" do
      allow(Rails.logger).to receive(:warn)

      leaves_of(imap_nested_message(12))

      expect(Rails.logger).to have_received(:warn).at_least(:once)
    end

    it "returns every leaf of a structure at the depth limit without logging" do
      allow(Rails.logger).to receive(:warn)

      leaves_of(imap_nested_message(5))

      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  describe "Leaf#text?" do
    def only(sexp) = described_class.leaves(imap_bodystructure(sexp)).sole

    it "is true for text/plain and text/html without a filename" do
      plain = only(%{("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" 5 1 NIL NIL NIL NIL)})
      html = only(%{("TEXT" "HTML" ("CHARSET" "UTF-8") NIL NIL "7BIT" 5 1 NIL NIL NIL NIL)})

      expect([ plain.text?, html.text? ]).to eq([ true, true ])
    end

    it "is false for other text types and for non-text types" do
      calendar = only(%{("TEXT" "CALENDAR" NIL NIL NIL "7BIT" 5 1 NIL NIL NIL NIL)})
      pdf = only(%{("APPLICATION" "PDF" NIL NIL NIL "BASE64" 5 NIL NIL NIL NIL)})

      expect([ calendar.text?, pdf.text? ]).to eq([ false, false ])
    end

    it "is false for a text part with a disposition filename, a content-type name or a location, like Mail#find_attachment" do
      by_disposition = only(%{("TEXT" "PLAIN" NIL NIL NIL "7BIT" 5 1 NIL ("ATTACHMENT" ("FILENAME" "a.txt")) NIL NIL)})
      by_name = only(%{("TEXT" "PLAIN" ("NAME" "a.txt") NIL NIL "7BIT" 5 1 NIL NIL NIL NIL)})
      by_location = only(%{("TEXT" "PLAIN" NIL NIL NIL "7BIT" 5 1 NIL NIL NIL "a.txt")})

      expect([ by_disposition, by_name, by_location ].map(&:text?)).to all(be(false))
    end

    it "agrees with ImapBodyParser on which parts of a fixture are body text" do
      message = imap_fixture("nested")

      expect(leaves_of(message).select(&:text?).map(&:path)).to eq(%w[1.1.1 1.1.2])
    end
  end

  describe "Leaf#attachment?" do
    it "is true for a part with a filename that is not inline" do
      leaves = leaves_of(imap_fixture("mixed_pdf"))

      expect(leaves.map { |l| [ l.path, l.attachment? ] }).to eq([ [ "1", false ], [ "2", true ] ])
    end

    it "is false for a part without a filename" do
      expect(leaves_of(imap_fixture("plain")).sole.attachment?).to be(false)
    end

    it "is true for a single-part PDF" do
      expect(leaves_of(imap_fixture("pdf_only")).sole).to have_attributes(path: "1", attachment?: true, text?: false)
    end
  end
end
