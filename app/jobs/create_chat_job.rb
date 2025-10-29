class CreateChatJob < ApplicationJob
  queue_as :default

  def perform(chat_application_id, chat_number)
    chat_application = ChatApplication.find(chat_application_id)

    # Create the chat in the database
    chat = chat_application.chats.create!(number: chat_number)

    # Atomically increment the counter
    ChatApplication.increment_counter(:chats_count, chat_application_id)
  rescue ActiveRecord::RecordInvalid => e
    # Log error if chat creation fails (e.g., duplicate number due to race condition)
    Rails.logger.error("CreateChatJob failed for chat_application #{chat_application_id}, number #{chat_number}: #{e.message}")
    raise
  end
end
