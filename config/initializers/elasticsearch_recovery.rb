# Elasticsearch Recovery Initializer
# Checks on startup if messages are missing from Elasticsearch and triggers reindexing if needed

Rails.application.config.after_initialize do
  # Skip in test environment
  next if Rails.env.test?

  # Run check in background thread to avoid blocking application startup
  Thread.new do
    # Wait for services to be fully ready
    sleep 10

    begin
      Rails.logger.info("ElasticsearchRecovery: Checking for indexing gaps...")

      # Get count of indexed messages
      search_response = Message.search('*', size: 0)
      indexed_count = search_response.results.total

      # Get count from database
      db_count = Message.count

      Rails.logger.info("ElasticsearchRecovery: Database has #{db_count} messages, Elasticsearch has #{indexed_count} indexed")

      # If there's a discrepancy, trigger reindexing
      if indexed_count < db_count
        missing_count = db_count - indexed_count
        Rails.logger.warn("ElasticsearchRecovery: Elasticsearch is missing #{missing_count} messages. Triggering reindex...")
        ReindexMessagesJob.perform_later
      elsif indexed_count > db_count
        # This shouldn't happen, but log it if it does
        Rails.logger.warn("ElasticsearchRecovery: Elasticsearch has MORE messages (#{indexed_count}) than database (#{db_count}). Consider rebuilding index.")
        ReindexMessagesJob.perform_later
      else
        Rails.logger.info("ElasticsearchRecovery: Elasticsearch is in sync with database")
      end
    rescue Faraday::ConnectionFailed, Elasticsearch::Transport::Transport::Error => e
      Rails.logger.error("ElasticsearchRecovery: Elasticsearch connection failed: #{e.message}")
      Rails.logger.info("ElasticsearchRecovery: Will retry reindexing on next request that uses search")
    rescue => e
      Rails.logger.error("ElasticsearchRecovery: Unexpected error during check: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
  end
end
