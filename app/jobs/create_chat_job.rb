# Background job to persist chats to MySQL
# Enqueued by ChatsController after getting sequential number from Redis
class CreateChatJob < ApplicationJob
  queue_as :default

  def perform(chat_application_id, chat_number)
    chat_application = ChatApplication.find(chat_application_id)

    # Create chat in MySQL
    chat_application.chats.create!(number: chat_number)

    # Update cached chat count
    ChatApplication.increment_counter(:chats_count, chat_application_id)

  rescue ActiveRecord::RecordNotUnique
    # Duplicate number detected by database unique constraint
    # Sidekiq will automatically retry this job
    Rails.logger.error("Duplicate chat number #{chat_number} for application #{chat_application_id}")
    raise
  end
end
