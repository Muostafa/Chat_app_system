# Elasticsearch client configuration for full-text search
# Used by Message model for searching message bodies
Elasticsearch::Model.client = Elasticsearch::Client.new(
  url: ENV.fetch('ELASTICSEARCH_URL', 'http://localhost:9200')
)
