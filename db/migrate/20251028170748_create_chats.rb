class CreateChats < ActiveRecord::Migration[8.1]
  def change
    create_table :chats do |t|
      t.references :chat_application, null: false, foreign_key: true
      t.integer :number, null: false
      t.integer :messages_count, default: 0, null: false

      t.timestamps
    end

    add_index :chats, [:chat_application_id, :number], unique: true
  end
end
