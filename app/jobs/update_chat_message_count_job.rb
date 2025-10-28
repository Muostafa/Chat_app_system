class UpdateChatMessageCountJob < ApplicationJob
  queue_as :default

  def perform(chat_id)
    chat = Chat.find(chat_id)
    chat.update(messages_count: chat.messages.count)
  rescue => e
    Rails.logger.error("UpdateChatMessageCountJob failed for chat #{chat_id}: #{e.message}")
  end
end
