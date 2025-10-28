require 'rails_helper'

RSpec.describe Chat, type: :model do
  describe 'validations' do
    let(:chat_application) { create(:chat_application) }

    it { is_expected.to validate_presence_of(:number) }

    it 'validates uniqueness of number scoped to chat_application' do
      chat1 = create(:chat, chat_application: chat_application, number: 1)
      chat2 = build(:chat, chat_application: chat_application, number: 1)
      expect(chat2).not_to be_valid
    end

    it 'allows same number in different applications' do
      app1 = create(:chat_application)
      app2 = create(:chat_application)
      chat1 = create(:chat, chat_application: app1, number: 1)
      chat2 = create(:chat, chat_application: app2, number: 1)
      expect(chat2).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:chat_application) }
    it { is_expected.to have_many(:messages).dependent(:destroy) }
  end

  describe 'initialization' do
    it 'sets messages_count to 0 by default' do
      chat = create(:chat)
      expect(chat.messages_count).to eq(0)
    end
  end
end
