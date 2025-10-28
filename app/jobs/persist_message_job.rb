class PersistMessageJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find(message_id)
    # Index the message in Elasticsearch
    Message.__elasticsearch__.index_document(message)
    # Queue job to update message count
    UpdateChatMessageCountJob.perform_later(message.chat_id)
  rescue => e
    Rails.logger.error("PersistMessageJob failed for message #{message_id}: #{e.message}")
  end
end
