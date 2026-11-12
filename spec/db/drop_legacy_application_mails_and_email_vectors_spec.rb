require "rails_helper"
require Rails.root.join("db/migrate/20261104090000_drop_legacy_application_mails_and_email_vectors")

RSpec.describe DropLegacyApplicationMailsAndEmailVectors, prosopite: false do
  let(:connection) { ActiveRecord::Base.connection }

  def table?(name) = connection.select_value("SELECT 1 FROM sqlite_master WHERE name = '#{name}'").present?

  def migrate_up = ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }

  it "drops the legacy table and the vec0 virtual table with its shadow tables" do
    connection.execute("CREATE TABLE application_mails (id integer PRIMARY KEY)")
    connection.execute("CREATE VIRTUAL TABLE email_vectors USING vec0(embedding float[4])")

    migrate_up

    expect(%w[application_mails email_vectors email_vectors_chunks email_vectors_rowids].map { |name| table?(name) }).to all(be(false))
  end

  it "does nothing on a database that never had them" do
    expect { migrate_up }.not_to raise_error
  end

  it "is irreversible" do
    expect { ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:down) } }
      .to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
