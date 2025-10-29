# Disable Elasticsearch indexing in tests
# The Elasticsearch callbacks are added dynamically, so we stub at the instance level
RSpec.configure do |config|
  config.before(:each) do
    # Stub Elasticsearch indexing methods to prevent actual ES calls
    allow_any_instance_of(Message).to receive(:__elasticsearch__).and_return(
      double('elasticsearch', index_document: true, update_document: true, delete_document: true)
    )
  end
end
