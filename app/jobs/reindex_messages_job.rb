class ReindexMessagesJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info("ReindexMessagesJob: Starting reindex of all messages...")

    begin
      # Use bulk import for efficiency - reindexes all messages from MySQL to Elasticsearch
      Message.__elasticsearch__.import force: true

      total_count = Message.count
      Rails.logger.info("ReindexMessagesJob: Successfully reindexed #{total_count} messages")
    rescue => e
      Rails.logger.error("ReindexMessagesJob: Failed to reindex messages: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      raise
    end
  end
end
