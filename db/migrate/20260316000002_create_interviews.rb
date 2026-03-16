class CreateInterviews < ActiveRecord::Migration[8.1]
  def change
    create_table :interviews do |t|
      t.string :company,              null: false
      t.string :job_title,            null: false
      t.string :status,               default: "pending_reply"
      t.date   :applied_at
      t.date   :rejected_at
      t.date   :first_interview_at
      t.date   :second_interview_at
      t.date   :third_interview_at
      t.date   :fourth_interview_at

      t.timestamps
    end

    add_index :interviews, [ :company, :job_title ], unique: true
  end
end
