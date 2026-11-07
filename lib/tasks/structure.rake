# FTS5 creates its own shadow tables (<name>_data/_idx/_docsize/_config); the dump lists them too and
# loading them fails ("object name reserved for internal use"), so drop them from structure.sql.
Rake::Task["db:schema:dump"].enhance do
  path = Rails.root.join("db/structure.sql")
  next unless path.exist?

  shadow = /^CREATE TABLE IF NOT EXISTS ['"]\w+_fts_(?:data|idx|docsize|config)['"].*\n/
  path.write(path.read.gsub(shadow, ""))
end
