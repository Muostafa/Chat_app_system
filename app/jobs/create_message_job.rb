# Background job to persist messages to MySQL and index in Elasticsearch
# Enqueued by MessagesController after getting sequential number from Redis
class CreateMessageJob < ApplicationJob
  queue_as :default

  def perform(chat_id, message_number, message_body)
    chat = Chat.find(chat_id)

    # Create message in MySQL (critical operation)
    message = chat.messages.create!(
      number: message_number,
      body: message_body
    )

    # Update cached message count
    Chat.increment_counter(:messages_count, chat_id)

    # Index in Elasticsearch (best-effort - don't fail job if this fails)
    index_to_elasticsearch(message)

  rescue ActiveRecord::RecordNotUnique
    # Duplicate number detected by database unique constraint
    # This is rare - means Redis gave same number twice
    # Sidekiq will automatically retry this job
    Rails.logger.error("Duplicate message number #{message_number} for chat #{chat_id}")
    raise
  end

  private

  def index_to_elasticsearch(message)
    Message.__elasticsearch__.index_document(message)
  rescue => e
    # Elasticsearch indexing failed - log it but don't fail the job
    # Message is still saved in MySQL, just not searchable yet
    Rails.logger.error("Elasticsearch indexing failed: #{e.message}")
  end
end
