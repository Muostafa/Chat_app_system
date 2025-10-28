Elasticsearch::Model.client = Elasticsearch::Client.new(
  urls: [ENV.fetch('ELASTICSEARCH_URL', 'http://localhost:9200')]
)
