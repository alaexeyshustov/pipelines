namespace :documents do
  desc "Scan every embedded Document for near-duplicates (GH #227); run after a backfill or a threshold change " \
       "(Setting document_dedup_threshold / ENV DOCUMENT_DEDUP_THRESHOLD, default 0.95). Idempotent."
  task detect_duplicates: :environment do
    threshold = Document::DetectDuplicates.threshold
    Document.find_each { |document| Document::DetectDuplicates.call(document, threshold:) }
    puts "#{DocumentDuplicate.count} duplicate pairs at similarity >= #{threshold}."
  end
end
