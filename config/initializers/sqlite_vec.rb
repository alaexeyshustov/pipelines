require "sqlite_vec"

# Load the sqlite-vec extension for every SQLite connection so vec0 virtual
# tables are available for embedding-based (RAG) queries.
module SqliteVecExtension
  def configure_connection
    super
    db = raw_connection
    db.enable_load_extension(true)
    SqliteVec.load(db)
    db.enable_load_extension(false)
  end
end

ActiveSupport.on_load(:active_record) do
  if defined?(ActiveRecord::ConnectionAdapters::SQLite3Adapter)
    ActiveSupport.on_load(:active_record_sqlite3adapter) { prepend SqliteVecExtension }
  end
end

# db:schema:load / db:test:prepare feed structure.sql to the sqlite3 CLI, which needs the extension to create the
# vec0 virtual tables.
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Tasks::DatabaseTasks.structure_load_flags = { sqlite3: [ "-cmd", %("#{".load #{SqliteVec.loadable_path}"}") ] }
end
