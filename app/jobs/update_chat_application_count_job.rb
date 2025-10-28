class UpdateChatApplicationCountJob < ApplicationJob
  queue_as :default

  def perform(chat_application_id)
    chat_application = ChatApplication.find(chat_application_id)
    chat_application.update(chats_count: chat_application.chats.count)
  rescue => e
    Rails.logger.error("UpdateChatApplicationCountJob failed for app #{chat_application_id}: #{e.message}")
  end
end
