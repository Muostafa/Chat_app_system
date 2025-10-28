require 'rails_helper'

RSpec.describe "Api::V1::Chats", type: :request do
  let!(:app) { create(:chat_application) }
  let(:base_url) { "/api/v1/chat_applications/#{app.token}/chats" }

  describe 'POST /api/v1/chat_applications/:token/chats' do
    it 'creates a new chat with sequential number' do
      expect {
        post base_url
      }.to change(Chat, :count).by(1)
    end

    it 'returns the created chat with number' do
      post base_url
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json).to have_key('number')
      expect(json['number']).to eq(1)
      expect(json['messages_count']).to eq(0)
    end

    it 'increments chat numbers sequentially' do
      post base_url
      post base_url
      post base_url

      chats = app.chats.order(:created_at)
      expect(chats[0].number).to eq(1)
      expect(chats[1].number).to eq(2)
      expect(chats[2].number).to eq(3)
    end

    it 'returns 404 for non-existent application' do
      post '/api/v1/chat_applications/invalid_token/chats'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/chat_applications/:token/chats' do
    let!(:chat1) { create(:chat, chat_application: app, number: 1) }
    let!(:chat2) { create(:chat, chat_application: app, number: 2) }

    it 'returns all chats for the application' do
      get base_url
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(2)
    end

    it 'returns chat numbers and message counts' do
      get base_url
      json = JSON.parse(response.body)
      expect(json[0]['number']).to eq(1)
      expect(json[1]['number']).to eq(2)
    end
  end

  describe 'GET /api/v1/chat_applications/:token/chats/:number' do
    let!(:chat) { create(:chat, chat_application: app, number: 5) }

    it 'returns the specific chat' do
      get "#{base_url}/5"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['number']).to eq(5)
    end

    it 'returns 404 for non-existent chat number' do
      get "#{base_url}/999"
      expect(response).to have_http_status(:not_found)
    end
  end
end
