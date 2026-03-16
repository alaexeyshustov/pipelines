class CreateApplicationMails < ActiveRecord::Migration[8.1]
  def change
    create_table :application_mails do |t|
      t.date   :date,       null: false
      t.string :provider,   null: false
      t.string :email_id,   null: false
      t.string :company
      t.string :job_title
      t.string :action

      t.timestamps
    end

    add_index :application_mails, :email_id, unique: true
    add_index :application_mails, :date
  end
end
