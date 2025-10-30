class CreateMessageJob < ApplicationJob
  queue_as :default

  def perform(chat_id, message_number, message_body)
    chat = Chat.find(chat_id)

    # Create the message in the database
    message = chat.messages.create!(number: message_number, body: message_body)

    # Atomically increment the counter
    Chat.increment_counter(:messages_count, chat_id)

    # Index the message in Elasticsearch with retry logic
    index_message_with_retry(message, message_number)
  rescue ActiveRecord::RecordInvalid => e
    # Log error if message creation fails (e.g., duplicate number due to race condition)
    Rails.logger.error("CreateMessageJob failed for chat #{chat_id}, number #{message_number}: #{e.message}")
    raise
  end

  private

  def index_message_with_retry(message, message_number, max_attempts: 3)
    attempts = 0

    max_attempts.times do |attempt|
      attempts = attempt + 1
      begin
        Message.__elasticsearch__.index_document(message)
        Rails.logger.info("CreateMessageJob: Successfully indexed message #{message_number} on attempt #{attempts}") if attempts > 1
        return
      rescue => e
        if attempts < max_attempts
          # Exponential backoff: 1s, 2s, 4s...
          sleep_time = 2 ** attempt
          Rails.logger.warn("CreateMessageJob: Elasticsearch indexing failed for message #{message_number} (attempt #{attempts}/#{max_attempts}): #{e.message}. Retrying in #{sleep_time}s...")
          sleep(sleep_time)
        else
          # Final attempt failed, log error but don't fail the job
          Rails.logger.error("CreateMessageJob: Elasticsearch indexing failed for message #{message_number} after #{max_attempts} attempts: #{e.message}")
          Rails.logger.error("Message is persisted in MySQL but not searchable. Run 'rails elasticsearch:reindex_messages' to fix.")
        end
      end
    end
  end
end
