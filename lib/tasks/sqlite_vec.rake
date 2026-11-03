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
# loading them fails ("object name reserved for internal use"), so drop them from structure.sql. Same for the
# vec0 shadow tables (<name>_info/_chunks/_rowids/_vector_chunksNN).
Rake::Task["db:schema:dump"].enhance do
  path = Rails.root.join("db/structure.sql")
  next unless path.exist?

  shadow = /^CREATE TABLE IF NOT EXISTS ['"]\w+_(?:fts_(?:data|idx|docsize|config)|vectors_(?:info|chunks|rowids|vector_chunks\d+))['"].*\n/
  sql = path.read.gsub(shadow, "")
  path.write(sql)
end
