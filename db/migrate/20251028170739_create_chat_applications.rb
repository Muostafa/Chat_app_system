class CreateChatApplications < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_applications do |t|
      t.string :name, null: false
      t.string :token, null: false
      t.integer :chats_count, default: 0, null: false

      t.timestamps
    end

    add_index :chat_applications, :token, unique: true
  end
end
