namespace :elasticsearch do
  desc "Reindex all messages into Elasticsearch"
  task reindex_messages: :environment do
    puts "=" * 80
    puts "Reindexing all messages into Elasticsearch..."
    puts "=" * 80

    begin
      # Get initial counts
      db_count = Message.count
      puts "\nDatabase contains #{db_count} messages"

      if db_count == 0
        puts "No messages to index. Exiting."
        exit 0
      end

      # Perform bulk import
      print "Importing messages... "
      Message.__elasticsearch__.import force: true
      puts "Done!"

      # Verify indexing
      sleep 2 # Give Elasticsearch a moment to process
      search_response = Message.search('*', size: 0)
      indexed_count = search_response.results.total

      puts "\nResults:"
      puts "  Database messages: #{db_count}"
      puts "  Indexed messages:  #{indexed_count}"

      if indexed_count == db_count
        puts "\n✓ Success! All messages are now indexed in Elasticsearch"
      elsif indexed_count < db_count
        puts "\n⚠ Warning: Only #{indexed_count}/#{db_count} messages were indexed"
        puts "  Try running the task again or check Elasticsearch logs"
      else
        puts "\n⚠ Warning: Elasticsearch has more messages (#{indexed_count}) than database (#{db_count})"
        puts "  This may indicate duplicate entries in the index"
      end

    rescue Faraday::ConnectionFailed => e
      puts "\n✗ Error: Could not connect to Elasticsearch"
      puts "  Make sure Elasticsearch is running (check docker-compose ps)"
      exit 1
    rescue => e
      puts "\n✗ Error: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end

    puts "=" * 80
  end

  desc "Check Elasticsearch indexing status"
  task check_status: :environment do
    puts "=" * 80
    puts "Elasticsearch Indexing Status"
    puts "=" * 80

    begin
      db_count = Message.count
      search_response = Message.search('*', size: 0)
      indexed_count = search_response.results.total

      puts "\nDatabase messages: #{db_count}"
      puts "Indexed messages:  #{indexed_count}"

      if indexed_count == db_count
        puts "\n✓ Status: In sync"
      elsif indexed_count < db_count
        missing = db_count - indexed_count
        puts "\n⚠ Status: Out of sync (#{missing} messages missing from index)"
        puts "  Run 'rails elasticsearch:reindex_messages' to fix"
      else
        extra = indexed_count - db_count
        puts "\n⚠ Status: Index has #{extra} extra documents"
        puts "  Run 'rails elasticsearch:reindex_messages' to rebuild index"
      end

    rescue Faraday::ConnectionFailed => e
      puts "\n✗ Error: Could not connect to Elasticsearch"
      puts "  Make sure Elasticsearch is running"
    rescue => e
      puts "\n✗ Error: #{e.message}"
    end

    puts "=" * 80
  end

  desc "Delete and recreate Elasticsearch index (WARNING: destructive)"
  task recreate_index: :environment do
    puts "=" * 80
    puts "WARNING: This will delete the entire Elasticsearch index!"
    puts "=" * 80
    print "\nAre you sure? (yes/no): "

    # Only prompt in interactive mode
    if STDIN.tty?
      confirmation = STDIN.gets.chomp
      unless confirmation.downcase == 'yes'
        puts "Aborted."
        exit 0
      end
    end

    begin
      print "Deleting index... "
      Message.__elasticsearch__.delete_index! rescue nil
      puts "Done!"

      print "Creating index... "
      Message.__elasticsearch__.create_index! force: true
      puts "Done!"

      puts "\nIndex recreated. Run 'rails elasticsearch:reindex_messages' to populate it."
    rescue => e
      puts "\n✗ Error: #{e.message}"
      exit 1
    end

    puts "=" * 80
  end
end
