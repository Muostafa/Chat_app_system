# Redis configuration for tests
RSpec.configure do |config|
  config.before(:each) do
    # Clear Redis before each test
    begin
      redis = Redis.new
      redis.flushdb
    rescue => e
      # Log but don't fail if Redis is not available
      Rails.logger.warn("Redis not available in tests: #{e.message}")
    end
  end
end
