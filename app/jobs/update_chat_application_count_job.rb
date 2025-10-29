class UpdateChatApplicationCountJob < ApplicationJob
  queue_as :default

  def perform(chat_application_id)
    chat_application = ChatApplication.find(chat_application_id)

    # Use database locking to prevent race conditions when multiple jobs run concurrently
    chat_application.with_lock do
      actual_count = chat_application.chats.count
      chat_application.update_column(:chats_count, actual_count)
    end
  rescue => e
    Rails.logger.error("UpdateChatApplicationCountJob failed for app #{chat_application_id}: #{e.message}")
  end
end
