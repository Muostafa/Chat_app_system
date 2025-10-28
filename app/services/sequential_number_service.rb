class SequentialNumberService
  def self.next_chat_number(chat_application_id)
    redis = Redis.new
    key = "chat_app:#{chat_application_id}:chat_counter"
    redis.incr(key)
  end

  def self.next_message_number(chat_id)
    redis = Redis.new
    key = "chat:#{chat_id}:message_counter"
    redis.incr(key)
  end

  def self.reset_chat_counter(chat_application_id)
    redis = Redis.new
    key = "chat_app:#{chat_application_id}:chat_counter"
    redis.del(key)
  end

  def self.reset_message_counter(chat_id)
    redis = Redis.new
    key = "chat:#{chat_id}:message_counter"
    redis.del(key)
  end
end
