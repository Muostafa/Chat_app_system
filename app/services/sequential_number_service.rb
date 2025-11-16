# Service object for generating sequential numbers using Redis atomic operations
# Uses Redis INCR command which is atomic - prevents race conditions under concurrency
class SequentialNumberService
  # Generate next sequential chat number for an application
  # Example: chat_app:1:chat_counter -> 1, 2, 3...
  def self.next_chat_number(chat_application_id)
    key = "chat_app:#{chat_application_id}:chat_counter"
    REDIS.incr(key)
  end

  # Generate next sequential message number for a chat
  # Example: chat:1:message_counter -> 1, 2, 3...
  def self.next_message_number(chat_id)
    key = "chat:#{chat_id}:message_counter"
    REDIS.incr(key)
  end
end
