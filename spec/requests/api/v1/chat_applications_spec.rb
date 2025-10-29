require 'rails_helper'

RSpec.describe "Api::V1::ChatApplications", type: :request do
  let(:valid_params) { { chat_application: { name: 'Test App' } } }
  let(:invalid_params) { { chat_application: { name: '' } } }

  describe 'POST /api/v1/chat_applications' do
    it 'creates a new chat application' do
      expect {
        post '/api/v1/chat_applications', params: valid_params
      }.to change(ChatApplication, :count).by(1)
    end

    it 'returns the created application with token' do
      post '/api/v1/chat_applications', params: valid_params
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json).to have_key('token')
      expect(json).to have_key('name')
      expect(json['chats_count']).to eq(0)
    end

    it 'returns validation errors' do
      post '/api/v1/chat_applications', params: invalid_params
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET /api/v1/chat_applications/:token' do
    let!(:chat_app) { create(:chat_application) }

    it 'returns the chat application' do
      get "/api/v1/chat_applications/#{chat_app.token}"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['token']).to eq(chat_app.token)
      expect(json['name']).to eq(chat_app.name)
    end

    it 'returns 404 for non-existent token' do
      get '/api/v1/chat_applications/invalid_token'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/chat_applications' do
    let!(:chat_app1) { create(:chat_application) }
    let!(:chat_app2) { create(:chat_application) }

    it 'returns all chat applications' do
      get '/api/v1/chat_applications'
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to be >= 2
      # Verify our created apps are in the response
      tokens = json.map { |app| app['token'] }
      expect(tokens).to include(chat_app1.token)
      expect(tokens).to include(chat_app2.token)
    end
  end

  describe 'PATCH /api/v1/chat_applications/:token' do
    let!(:chat_app) { create(:chat_application, name: 'Old Name') }
    let(:update_params) { { chat_application: { name: 'New Name' } } }

    it 'updates the chat application' do
      patch "/api/v1/chat_applications/#{chat_app.token}", params: update_params
      expect(response).to have_http_status(:ok)
      chat_app.reload
      expect(chat_app.name).to eq('New Name')
    end

    it 'returns the updated application' do
      patch "/api/v1/chat_applications/#{chat_app.token}", params: update_params
      json = JSON.parse(response.body)
      expect(json['name']).to eq('New Name')
    end
  end
end
