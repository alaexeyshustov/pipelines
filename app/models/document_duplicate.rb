# A candidate pair of semantically near-identical Documents (GH #227). Stored once in canonical order
# (+document+ has the lower id), so detection is idempotent. Nothing is merged or hidden: the user confirms or
# dismisses the pair, and a dismissed pair is never flagged again.
class DocumentDuplicate < ApplicationRecord
  DEFAULT_THRESHOLD = 0.95

  belongs_to :document
  belongs_to :duplicate, class_name: "Document"

  enum :status, { pending: "pending", confirmed: "confirmed", dismissed: "dismissed" }, default: :pending

  validates :similarity, presence: true
  validate :distinct_documents

  scope :involving, ->(document) { where(document:).or(where(duplicate: document)) }

  # Minimum cosine similarity for a pair: Setting "document_dedup_threshold", then ENV DOCUMENT_DEDUP_THRESHOLD,
  # then 0.95.
  def self.threshold
    Float(Setting.fetch("document_dedup_threshold") || ENV.fetch("DOCUMENT_DEDUP_THRESHOLD", DEFAULT_THRESHOLD))
  end

  # The pairs of +document+ still worth showing (everything but dismissed), with both documents loaded.
  def self.candidates_for(document)
    involving(document).where.not(status: :dismissed).includes(:document, :duplicate).order(:id)
  end

  # Records the pair; only a pending pair gets its similarity refreshed, a confirmed or dismissed one is left alone.
  def self.flag!(first, second, similarity:)
    low, high = [ first, second ].sort_by(&:id)
    record = find_or_initialize_by(document: low, duplicate: high)
    record.similarity = similarity if record.new_record? || record.pending?
    record.save!
    record
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # flag! for many neighbours of +document+ at once: +matches+ are [other document, similarity] pairs. The existing
  # pairs are loaded in one query instead of one lookup per neighbour.
  def self.flag_all!(document, matches)
    existing = involving(document).index_by { |pair| [ pair.document_id, pair.duplicate_id ] }
    matches.map do |other, similarity|
      flag_known!(existing, document, other, similarity)
    rescue ActiveRecord::RecordNotUnique
      flag!(document, other, similarity:)
    end
  end

  def self.flag_known!(existing, document, other, similarity)
    low, high = [ document, other ].sort_by(&:id)
    record = existing[[ low.id, high.id ]] || new(document: low, duplicate: high)
    record.similarity = similarity if record.new_record? || record.pending?
    record.save!
    record
  end
  private_class_method :flag_known!

  # The document on the other side of the pair.
  def other(from)
    from.id == document_id ? duplicate : document
  end

  private

  def distinct_documents
    errors.add(:duplicate, "must differ from the document") if document_id == duplicate_id
  end
end
