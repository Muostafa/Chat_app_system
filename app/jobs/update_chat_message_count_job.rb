class UpdateChatMessageCountJob < ApplicationJob
  queue_as :default

  def perform(chat_id)
    chat = Chat.find(chat_id)

    # Use database locking to prevent race conditions when multiple jobs run concurrently
    chat.with_lock do
      actual_count = chat.messages.count
      chat.update_column(:messages_count, actual_count)
    end
  rescue => e
    Rails.logger.error("UpdateChatMessageCountJob failed for chat #{chat_id}: #{e.message}")
  end
end
