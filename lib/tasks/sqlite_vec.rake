# Ensure the sqlite-vec extension is loaded before db:schema:load so the vec0
# virtual table in structure.sql can be created in the test database.
Rake::Task["db:schema:load"].enhance([ "sqlite_vec:load_extension" ])

namespace :sqlite_vec do
  task load_extension: :environment do
    # Touching the connection pool causes SqliteVecExtension#configure_connection
    # to run, loading the vec0 module before structure.sql is executed.
    ActiveRecord::Base.connection
  end
end

# FTS5 creates its own shadow tables (<name>_data/_idx/_docsize/_config); the dump lists them too and
# loading them fails ("object name reserved for internal use"), so drop them from structure.sql.
Rake::Task["db:schema:dump"].enhance do
  path = Rails.root.join("db/structure.sql")
  next unless path.exist?

  sql = path.read.gsub(/^CREATE TABLE IF NOT EXISTS '\w+_fts_(?:data|idx|docsize|config)'.*\n/, "")
  path.write(sql)
end
