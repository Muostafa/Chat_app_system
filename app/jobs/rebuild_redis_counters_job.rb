class RebuildRedisCountersJob < ApplicationJob
  queue_as :default

  def perform
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))

    rebuild_chat_counters(redis)
    rebuild_message_counters(redis)

    Rails.logger.info("RebuildRedisCountersJob completed successfully")
  end

  private

  def rebuild_chat_counters(redis)
    ChatApplication.find_each do |app|
      # Get the highest chat number for this application
      max_chat_number = app.chats.maximum(:number) || 0

      # Set Redis counter to this value
      key = "chat_app:#{app.id}:chat_counter"
      redis.set(key, max_chat_number)

      Rails.logger.info("Rebuilt chat counter for app #{app.id} (#{app.name}): #{max_chat_number}")
    end
  end

  def rebuild_message_counters(redis)
    Chat.find_each do |chat|
      # Get the highest message number for this chat
      max_message_number = chat.messages.maximum(:number) || 0

      # Set Redis counter to this value
      key = "chat:#{chat.id}:message_counter"
      redis.set(key, max_message_number)

      Rails.logger.info("Rebuilt message counter for chat #{chat.id}: #{max_message_number}")
    end
  end
end
