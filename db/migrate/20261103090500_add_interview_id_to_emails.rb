# GH #228: which emails fed an Interview. Nullable; emails survive an Interview being removed.
# Plain ALTER TABLE: add_reference with a foreign key makes SQLite rebuild the table, which drops the
# emails_fts triggers.
class AddInterviewIdToEmails < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TABLE emails ADD COLUMN interview_id integer REFERENCES interviews (id) ON DELETE SET NULL"
    add_index :emails, :interview_id
  end

  def down
    remove_index :emails, :interview_id
    execute "ALTER TABLE emails DROP COLUMN interview_id"
  end
end
