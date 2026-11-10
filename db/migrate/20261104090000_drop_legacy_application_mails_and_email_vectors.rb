# GH #228: ApplicationMail is replaced by tagged Emails feeding Interviews, and email_vectors (a sqlite-vec vec0 table)
# was unused. Databases created before the #215 redesign still have both; fresh ones never do (hence IF EXISTS).
# No data migration. Dropping a vec0 virtual table needs the sqlite-vec module, which is loaded on every connection
# (config/initializers/neighbor.rb); should that fail anyway, the shadow tables are dropped explicitly so the
# migration still completes.
class DropLegacyApplicationMailsAndEmailVectors < ActiveRecord::Migration[8.1]
  SHADOW_SUFFIXES = %w[info chunks rowids vector_chunks00].freeze

  def up
    drop_email_vectors
    execute "DROP TABLE IF EXISTS application_mails"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def drop_email_vectors
    execute "DROP TABLE IF EXISTS email_vectors"
  rescue ActiveRecord::StatementInvalid => error
    say "DROP TABLE email_vectors failed (#{error.message}); dropping its shadow tables instead"
    SHADOW_SUFFIXES.each { |suffix| execute "DROP TABLE IF EXISTS email_vectors_#{suffix}" }
  end
end
