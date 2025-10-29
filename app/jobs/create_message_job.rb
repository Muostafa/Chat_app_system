class CreateMessageJob < ApplicationJob
  queue_as :default

  def perform(chat_id, message_number, message_body)
    chat = Chat.find(chat_id)

    # Create the message in the database
    message = chat.messages.create!(number: message_number, body: message_body)

    # Index the message in Elasticsearch
    Message.__elasticsearch__.index_document(message)

    # Atomically increment the counter
    Chat.increment_counter(:messages_count, chat_id)
  rescue ActiveRecord::RecordInvalid => e
    # Log error if message creation fails (e.g., duplicate number due to race condition)
    Rails.logger.error("CreateMessageJob failed for chat #{chat_id}, number #{message_number}: #{e.message}")
    raise
  rescue => e
    # Log Elasticsearch indexing errors but don't fail the job
    Rails.logger.error("CreateMessageJob: Elasticsearch indexing failed for message #{message_number}: #{e.message}")
    # Message is still persisted in MySQL, counter still incremented
  end
end
