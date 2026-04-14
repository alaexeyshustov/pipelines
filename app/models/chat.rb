class Chat < ApplicationRecord
  acts_as_chat

  has_many :action_runs, class_name: "Orchestration::ActionRun", dependent: :nullify
end
