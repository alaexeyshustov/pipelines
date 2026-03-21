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
