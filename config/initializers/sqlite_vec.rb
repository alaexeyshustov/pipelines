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
    ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(SqliteVecExtension)
  end
end
