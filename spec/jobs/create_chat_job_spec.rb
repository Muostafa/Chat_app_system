require 'rails_helper'

RSpec.describe CreateChatJob, type: :job do
  let!(:app) { create(:chat_application) }

  describe '#perform' do
    it 'creates a chat with the specified number' do
      expect {
        described_class.perform_now(app.id, 1)
      }.to change(Chat, :count).by(1)

      chat = app.chats.last
      expect(chat.number).to eq(1)
    end

    it 'increments the chats_count for the application' do
      initial_count = app.chats_count
      described_class.perform_now(app.id, 1)
      expect(app.reload.chats_count).to eq(initial_count + 1)
    end

    it 'raises an error if chat creation fails' do
      # Create a chat with number 1 first
      create(:chat, chat_application: app, number: 1)

      # Attempt to create another chat with the same number (should fail due to uniqueness)
      expect {
        described_class.perform_now(app.id, 1)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'logs error and raises when RecordInvalid occurs' do
      create(:chat, chat_application: app, number: 1)

      allow(Rails.logger).to receive(:error)

      expect {
        described_class.perform_now(app.id, 1)
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(Rails.logger).to have_received(:error).with(/CreateChatJob failed/)
    end
  end
end
