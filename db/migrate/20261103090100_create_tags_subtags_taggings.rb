class CreateTagsSubtagsTaggings < ActiveRecord::Migration[8.1]
  def change
    create_table :tags do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :tags, :name, unique: true

    create_table :subtags do |t|
      t.references :tag, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :subtags, %i[tag_id name], unique: true

    create_table :taggings do |t|
      t.references :taggable, polymorphic: true, null: false, index: false
      t.references :tag, null: false, foreign_key: true
      t.references :subtag, foreign_key: true
      t.string :source, null: false, default: "llm"
      t.float :confidence
      t.timestamps
    end
    add_index :taggings, %i[taggable_type taggable_id tag_id], unique: true
  end
end
