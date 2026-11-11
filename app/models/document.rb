# A pdf/doc(x)/image reduced to its extracted text (markdown); the file itself is never stored.
# The original is re-fetched live via +source_ref+ (see Document::Download). +documents_fts+ (FTS5, external
# content) is kept in sync by DB triggers.
class Document < ApplicationRecord
  include Taggable
  include FtsSearchable
  include Embeddable

  EMAIL_ATTACHMENT = "email_attachment".freeze
  DRIVE = "drive".freeze
  SOURCES = [ EMAIL_ATTACHMENT, DRIVE ].freeze
  # source_ref["provider"] of a Drive Document (not an email provider).
  DRIVE_REF_PROVIDER = "drive".freeze

  belongs_to :email, optional: true
  has_many :document_duplicates, dependent: :destroy
  has_many :reverse_document_duplicates, class_name: "DocumentDuplicate", foreign_key: :duplicate_id,
                                         inverse_of: :duplicate, dependent: :destroy

  validates :title, :mime_type, :checksum, presence: true
  validates :text, exclusion: { in: [ nil ] }
  validates :checksum, uniqueness: true
  validates :source, inclusion: { in: SOURCES }

  # Title and text, the text Embeddings::Text embeds.
  def embedding_parts
    [ title, text ]
  end

  # The parsed +source_url+ when it is a well-formed http(s) URL a link may point at, else nil (a URL with spaces,
  # a javascript: URL or a blank one).
  def openable_source_uri
    uri = URI.parse(source_url.to_s)
    uri if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  # Idempotent on checksum: re-ingesting the same file returns the existing Document.
  def self.ingest!(attributes)
    attributes = attributes.to_h.with_indifferent_access
    find_by(checksum: attributes[:checksum]) || create!(attributes)
  rescue ActiveRecord::RecordNotUnique
    find_by!(checksum: attributes[:checksum])
  end
end
