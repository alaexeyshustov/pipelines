# A pdf/doc(x)/image reduced to its extracted text (markdown); the file itself is never stored.
# The original is re-fetched live via +source_ref+ (see Document::Download). +documents_fts+ (FTS5, external
# content) is kept in sync by DB triggers.
class Document < ApplicationRecord
  include Taggable
  include FtsSearchable

  SOURCES = %w[email_attachment drive].freeze

  belongs_to :email, optional: true

  validates :title, :mime_type, :checksum, presence: true
  validates :text, exclusion: { in: [ nil ] }
  validates :checksum, uniqueness: true
  validates :source, inclusion: { in: SOURCES }

  # Idempotent on checksum: re-ingesting the same file returns the existing Document.
  def self.ingest!(attributes)
    attributes = attributes.to_h.with_indifferent_access
    find_by(checksum: attributes[:checksum]) || create!(attributes)
  rescue ActiveRecord::RecordNotUnique
    find_by!(checksum: attributes[:checksum])
  end
end
