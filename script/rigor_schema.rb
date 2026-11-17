# Writes tmp/rigor/schema.rb for rigor-activerecord, which parses only PostgreSQL
# structure.sql. Rails' Ruby dumper crashes on our multi-line FTS5 virtual tables,
# so load the SQL into memory and skip them. Run: bundle exec ruby script/rigor_schema.rb
require "active_record"
require "fileutils"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.connection.raw_connection.execute_batch(File.read("db/structure.sql").gsub(%r{/\*.*?\*/}m, ""))
ActiveRecord::SchemaDumper.ignore_tables = [ /_fts/ ]
FileUtils.mkdir_p("tmp/rigor")
File.open("tmp/rigor/schema.rb", "w") { |f| ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, f) }
