class SyncCountersJob < ApplicationJob
  queue_as :default

  def perform
    # Sync all chat application counters
    sync_chat_application_counters

    # Sync all chat message counters
    sync_chat_message_counters
  end

  private

  def sync_chat_application_counters
    ChatApplication.find_each do |app|
      app.with_lock do
        actual_count = app.chats.count
        app.update_column(:chats_count, actual_count) if app.chats_count != actual_count
      end
    rescue => e
      Rails.logger.error("SyncCountersJob: Failed to sync chats_count for ChatApplication #{app.id}: #{e.message}")
    end
  end

  def sync_chat_message_counters
    Chat.find_each do |chat|
      chat.with_lock do
        actual_count = chat.messages.count
        chat.update_column(:messages_count, actual_count) if chat.messages_count != actual_count
      end
    rescue => e
      Rails.logger.error("SyncCountersJob: Failed to sync messages_count for Chat #{chat.id}: #{e.message}")
    end
  end
end
