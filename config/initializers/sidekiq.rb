# Sidekiq background job processing configuration
# Server: Sidekiq workers that process jobs from the queue
# Client: Rails app that enqueues jobs to the queue

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end
