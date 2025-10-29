require 'rails_helper'

RSpec.describe RebuildRedisCountersJob, type: :job do
  let(:redis) { Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')) }

  before do
    # Clear Redis before each test
    redis.flushdb
  end

  describe '#perform' do
    context 'with chat applications and chats' do
      let!(:app1) { create(:chat_application) }
      let!(:app2) { create(:chat_application) }
      let!(:chat1) { create(:chat, chat_application: app1, number: 1) }
      let!(:chat2) { create(:chat, chat_application: app1, number: 2) }
      let!(:chat3) { create(:chat, chat_application: app2, number: 1) }

      it 'rebuilds chat counters for all applications' do
        described_class.perform_now

        expect(redis.get("chat_app:#{app1.id}:chat_counter").to_i).to eq(2)
        expect(redis.get("chat_app:#{app2.id}:chat_counter").to_i).to eq(1)
      end

      it 'handles applications with no chats' do
        app3 = create(:chat_application)

        described_class.perform_now

        expect(redis.get("chat_app:#{app3.id}:chat_counter").to_i).to eq(0)
      end
    end

    context 'with messages' do
      let!(:app) { create(:chat_application) }
      let!(:chat1) { create(:chat, chat_application: app, number: 1) }
      let!(:chat2) { create(:chat, chat_application: app, number: 2) }
      let!(:msg1) { create(:message, chat: chat1, number: 1, body: 'Message 1') }
      let!(:msg2) { create(:message, chat: chat1, number: 2, body: 'Message 2') }
      let!(:msg3) { create(:message, chat: chat1, number: 3, body: 'Message 3') }
      let!(:msg4) { create(:message, chat: chat2, number: 1, body: 'Message 1 in chat 2') }

      it 'rebuilds message counters for all chats' do
        described_class.perform_now

        expect(redis.get("chat:#{chat1.id}:message_counter").to_i).to eq(3)
        expect(redis.get("chat:#{chat2.id}:message_counter").to_i).to eq(1)
      end

      it 'handles chats with no messages' do
        chat3 = create(:chat, chat_application: app, number: 3)

        described_class.perform_now

        expect(redis.get("chat:#{chat3.id}:message_counter").to_i).to eq(0)
      end
    end

    context 'when Redis counters are already correct' do
      let!(:app) { create(:chat_application) }
      let!(:chat) { create(:chat, chat_application: app, number: 5) }

      before do
        # Pre-set Redis counters
        redis.set("chat_app:#{app.id}:chat_counter", 5)
      end

      it 'overwrites existing counters' do
        described_class.perform_now

        # Should be overwritten with correct value from database
        expect(redis.get("chat_app:#{app.id}:chat_counter").to_i).to eq(5)
      end
    end

    context 'when Redis counters are inconsistent (too low)' do
      let!(:app) { create(:chat_application) }
      let!(:chat1) { create(:chat, chat_application: app, number: 1) }
      let!(:chat2) { create(:chat, chat_application: app, number: 2) }
      let!(:chat3) { create(:chat, chat_application: app, number: 3) }

      before do
        # Simulate Redis crash - counter is behind
        redis.set("chat_app:#{app.id}:chat_counter", 1)
      end

      it 'fixes inconsistent counters' do
        described_class.perform_now

        expect(redis.get("chat_app:#{app.id}:chat_counter").to_i).to eq(3)
      end
    end

    context 'logging' do
      let!(:app) { create(:chat_application, name: 'Test App') }
      let!(:chat) { create(:chat, chat_application: app, number: 1) }

      it 'logs completion message' do
        # Allow any order for the info calls
        allow(Rails.logger).to receive(:info)

        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with(/RebuildRedisCountersJob completed successfully/)
        expect(Rails.logger).to have_received(:info).with(/Rebuilt chat counter for app #{app.id}/)
        expect(Rails.logger).to have_received(:info).with(/Rebuilt message counter for chat #{chat.id}/)
      end
    end
  end
end
