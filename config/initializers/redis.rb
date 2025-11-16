# Global Redis connection for the application
# Used by SequentialNumberService for atomic INCR operations
REDIS = Redis.new(
  url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
)
