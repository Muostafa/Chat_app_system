# Redis Recovery Initializer
# Checks Redis counter consistency on Rails startup and triggers recovery if needed

Rails.application.config.after_initialize do
  # Only run in development and production, skip in test environment
  next if Rails.env.test?

  # Run after a short delay to ensure all services are fully initialized
  Thread.new do
    sleep 5 # Wait for services to be ready

    begin
      redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))

      # Check if Redis counters need rebuilding
      needs_rebuild = check_redis_consistency(redis)

      if needs_rebuild
        Rails.logger.warn("Redis counter inconsistency detected! Triggering RebuildRedisCountersJob...")
        RebuildRedisCountersJob.perform_later
      else
        Rails.logger.info("Redis counters are consistent with database")
      end
    rescue => e
      Rails.logger.error("Redis recovery check failed: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
  end
end

def check_redis_consistency(redis)
  # Sample a few applications to check consistency
  sample_size = [ChatApplication.count, 5].min

  return false if sample_size == 0

  ChatApplication.limit(sample_size).each do |app|
    max_chat_number = app.chats.maximum(:number) || 0
    redis_counter = redis.get("chat_app:#{app.id}:chat_counter").to_i

    if redis_counter < max_chat_number
      Rails.logger.warn("Inconsistency found for app #{app.id}: Redis=#{redis_counter}, DB=#{max_chat_number}")
      return true
    end
  end

  # Sample a few chats to check message counter consistency
  sample_chats = Chat.limit(5)

  sample_chats.each do |chat|
    max_message_number = chat.messages.maximum(:number) || 0
    redis_counter = redis.get("chat:#{chat.id}:message_counter").to_i

    if redis_counter < max_message_number
      Rails.logger.warn("Inconsistency found for chat #{chat.id}: Redis=#{redis_counter}, DB=#{max_message_number}")
      return true
    end
  end

  false
rescue => e
  Rails.logger.error("Error checking Redis consistency: #{e.message}")
  false
end
