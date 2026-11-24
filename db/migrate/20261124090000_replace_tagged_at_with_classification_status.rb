# GH #248: emails.tagged_at / documents.tagged_at become a string classification_status
# (pending | tagged | untagged | failed), so "analysed, no tags" and "classification failed" are distinguishable from
# the untagged backlog. No data is carried over: the app held no data when this shipped, every row starts pending.
#
# Plain SQL on purpose: no app models. The old column is dropped with raw ALTER TABLE ... DROP COLUMN, never
# remove_column: on SQLite that rebuilds the table and silently drops the emails_fts_* / documents_fts_* triggers.
# (DROP COLUMN fails on an indexed column, so down drops the new indexes first; it needs SQLite 3.35+.)
class ReplaceTaggedAtWithClassificationStatus < ActiveRecord::Migration[8.1]
  TABLES = %w[emails documents].freeze

  def up
    TABLES.each { |table| add_column table, :classification_status, :string, null: false, default: "pending" }

    add_index :emails, %i[provider classification_status]
    add_index :documents, :classification_status

    TABLES.each { |table| execute "ALTER TABLE #{table} DROP COLUMN tagged_at" }
  end

  def down
    TABLES.each { |table| add_column table, :tagged_at, :datetime }

    remove_index :emails, %i[provider classification_status]
    remove_index :documents, :classification_status

    TABLES.each { |table| execute "ALTER TABLE #{table} DROP COLUMN classification_status" }
  end
end
