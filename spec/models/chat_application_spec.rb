require 'rails_helper'

RSpec.describe ChatApplication, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:token) }
    it { is_expected.to validate_uniqueness_of(:token) }
  end

  describe 'associations' do
    it { is_expected.to have_many(:chats).dependent(:destroy) }
  end

  describe 'callbacks' do
    it 'generates a token before creation' do
      app = build(:chat_application)
      expect(app.token).to be_nil
      app.save
      expect(app.token).to be_present
    end

    it 'generates a unique token' do
      app1 = create(:chat_application)
      app2 = build(:chat_application)
      app2.save
      expect(app2.token).not_to eq(app1.token)
    end
  end

  describe 'initialization' do
    it 'sets chats_count to 0 by default' do
      app = create(:chat_application)
      expect(app.chats_count).to eq(0)
    end
  end
end
