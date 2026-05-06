class SeedEvaDatasetFromChats < ActiveRecord::Migration[8.1]
  def up
    dataset = Leva::Dataset.find_or_create_by!(name: "Historical Conversations") do |d|
      d.description = "Dataset created from historical Chat records for evaluation purposes."
    end

    # Insert chats as dataset records if they are not already present
    Chat.includes(:messages).find_each do |chat|
      # Skip chats without messages to keep the dataset meaningful
      next if chat.messages.empty?

      Leva::DatasetRecord.find_or_create_by!(
        dataset:    dataset,
        recordable: chat
      )
    end
  end

  def down
    dataset = Leva::Dataset.find_by(name: "Historical Conversations")
    dataset&.destroy
  end
end
