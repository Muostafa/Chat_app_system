require 'rails_helper'

RSpec.describe Message, type: :model do
  describe 'validations' do
    let(:chat) { create(:chat) }

    it { is_expected.to validate_presence_of(:body) }
    it { is_expected.to validate_presence_of(:number) }

    it 'validates uniqueness of number scoped to chat' do
      msg1 = create(:message, chat: chat, number: 1)
      msg2 = build(:message, chat: chat, number: 1)
      expect(msg2).not_to be_valid
    end

    it 'allows same number in different chats' do
      chat1 = create(:chat)
      chat2 = create(:chat)
      msg1 = create(:message, chat: chat1, number: 1)
      msg2 = create(:message, chat: chat2, number: 1)
      expect(msg2).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:chat) }
  end

  describe 'elasticsearch integration' do
    it 'includes elasticsearch modules' do
      expect(Message.included_modules).to include(Elasticsearch::Model)
    end
  end
end
