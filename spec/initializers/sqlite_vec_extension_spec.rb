require "rails_helper"

# `configure_connection` runs once per physical connection, at the point that
# connection is established -- not on every pool checkout. RSpec's primary AR
# connection is already established (and already ran the *original*
# `configure_connection`) long before this example runs, so asserting against
# `ActiveRecord::Base.connection` would pass even if the method body were
# broken. This spec instead opens a genuinely new, independent connection pool
# so its single connection's `configure_connection` call actually executes the
# current method body (see .omc/plans/fix-mutation-testing-ci.md, acceptance
# criterion 9, and docs/claude/gotchas.md on db:schema:load bypassing this
# hook entirely -- irrelevant here since we never touch the schema-loaded
# email_vectors table, only the extension-provided vec_version() function).
RSpec.describe "SqliteVecExtension" do
  it "loads the sqlite-vec extension on a freshly established connection" do
    config = ActiveRecord::Base.connection_db_config
    handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
    pool = handler.establish_connection(config)

    begin
      version = pool.with_connection { |conn| conn.execute("SELECT vec_version()") }
      expect(version.first.values.first).to match(/\Av\d+\.\d+\.\d+\z/)
    ensure
      pool.disconnect!
    end
  end
end
