# Simple health check endpoint for monitoring service availability
# Used by Docker, Kubernetes, or load balancers to verify the app is running
class HealthController < ApplicationController
  def index
    # Check connectivity to all critical services
    checks = {
      mysql: check_mysql,
      redis: check_redis,
      elasticsearch: check_elasticsearch
    }

    # Determine overall status
    all_healthy = checks.values.all? { |check| check[:status] == 'ok' }

    render json: {
      status: all_healthy ? 'healthy' : 'unhealthy',
      timestamp: Time.current.iso8601,
      services: checks
    }, status: all_healthy ? :ok : :service_unavailable
  rescue => e
    render json: {
      status: 'error',
      error: e.message,
      timestamp: Time.current.iso8601
    }, status: :internal_server_error
  end

  private

  def check_mysql
    ActiveRecord::Base.connection.execute('SELECT 1')
    { status: 'ok' }
  rescue => e
    { status: 'error', message: e.message }
  end

  def check_redis
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    redis.ping
    { status: 'ok' }
  rescue => e
    { status: 'error', message: e.message }
  end

  def check_elasticsearch
    Elasticsearch::Model.client.ping
    { status: 'ok' }
  rescue => e
    { status: 'error', message: e.message }
  end
end
