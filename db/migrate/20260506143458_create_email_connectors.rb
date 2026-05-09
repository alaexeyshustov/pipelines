class CreateEmailConnectors < ActiveRecord::Migration[8.1]
  def change
    create_table :email_connectors do |t|
      t.string :name, null: false
      t.string :provider, null: false
      t.text :configuration
      t.boolean :enabled, default: true, null: false
      t.datetime :last_connected_at
      t.string :status

      t.timestamps
    end
  end
end
