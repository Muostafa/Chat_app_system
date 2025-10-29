require 'rails_helper'

RSpec.describe PersistMessageJob, type: :job do
  let!(:app) { create(:chat_application) }
  let!(:chat) { create(:chat, chat_application: app, number: 1) }
  let!(:message) { create(:message, chat: chat, number: 1, body: 'Test message') }

  describe '#perform' do
    it 'attempts to index the message in Elasticsearch' do
      # The job uses Message.__elasticsearch__.index_document
      # We need to create a double for the class method
      es_double = double('elasticsearch')
      allow(Message).to receive(:__elasticsearch__).and_return(es_double)
      allow(es_double).to receive(:index_document).and_return(true)

      described_class.perform_now(message.id)

      expect(es_double).to have_received(:index_document).with(message)
    end

    it 'queues UpdateChatMessageCountJob' do
      # Stub ES to avoid errors
      es_double = double('elasticsearch')
      allow(Message).to receive(:__elasticsearch__).and_return(es_double)
      allow(es_double).to receive(:index_document).and_return(true)

      # Spy on the UpdateChatMessageCountJob to verify it's called
      allow(UpdateChatMessageCountJob).to receive(:perform_later)

      described_class.perform_now(message.id)

      expect(UpdateChatMessageCountJob).to have_received(:perform_later).with(chat.id)
    end

    it 'logs error when Elasticsearch indexing fails' do
      es_double = double('elasticsearch')
      allow(Message).to receive(:__elasticsearch__).and_return(es_double)
      allow(es_double).to receive(:index_document).and_raise(StandardError.new('ES Error'))
      allow(Rails.logger).to receive(:error)

      # Should not raise, just log
      expect {
        described_class.perform_now(message.id)
      }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(/PersistMessageJob failed/)
    end
  end
end
