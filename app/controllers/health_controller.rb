class HealthController < ApplicationController
  # Health check endpoint to monitor Redis counter consistency
  # GET /health/redis_counters
  def redis_counters
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))

    results = {
      status: 'healthy',
      checked_at: Time.current.iso8601,
      chat_applications: [],
      chats: [],
      warnings: []
    }

    # Check a sample of chat applications
    sample_apps = ChatApplication.limit(10)

    sample_apps.each do |app|
      max_db = app.chats.maximum(:number) || 0
      redis_counter = redis.get("chat_app:#{app.id}:chat_counter").to_i

      app_result = {
        id: app.id,
        name: app.name,
        redis_counter: redis_counter,
        db_max: max_db,
        consistent: redis_counter >= max_db
      }

      results[:chat_applications] << app_result

      if redis_counter < max_db
        results[:status] = 'warning'
        results[:warnings] << "ChatApplication #{app.id} (#{app.name}): Redis counter (#{redis_counter}) < DB max (#{max_db})"
      end
    end

    # Check a sample of chats
    sample_chats = Chat.limit(10)

    sample_chats.each do |chat|
      max_db = chat.messages.maximum(:number) || 0
      redis_counter = redis.get("chat:#{chat.id}:message_counter").to_i

      chat_result = {
        id: chat.id,
        chat_application_id: chat.chat_application_id,
        redis_counter: redis_counter,
        db_max: max_db,
        consistent: redis_counter >= max_db
      }

      results[:chats] << chat_result

      if redis_counter < max_db
        results[:status] = 'warning'
        results[:warnings] << "Chat #{chat.id}: Redis counter (#{redis_counter}) < DB max (#{max_db})"
      end
    end

    # Return appropriate HTTP status
    status_code = results[:status] == 'healthy' ? :ok : :service_unavailable

    render json: results, status: status_code
  rescue => e
    render json: {
      status: 'error',
      error: e.message,
      checked_at: Time.current.iso8601
    }, status: :internal_server_error
  end
end
