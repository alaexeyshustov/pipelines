# GH #228: ApplicationMail is replaced by tagged Emails feeding Interviews; email_vectors (sqlite-vec vec0) was unused.
# No data migration. The shadow tables are dropped explicitly: without the sqlite-vec extension loaded for the
# DROP, SQLite can leave them behind.
class DropApplicationMailsAndEmailVectors < ActiveRecord::Migration[8.1]
  def up
    execute "DROP TABLE IF EXISTS email_vectors"
    %w[info chunks rowids vector_chunks00].each { |suffix| execute "DROP TABLE IF EXISTS email_vectors_#{suffix}" }
    execute "DROP TABLE IF EXISTS application_mails"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
