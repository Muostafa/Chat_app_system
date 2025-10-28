require 'rails_helper'

RSpec.describe "Api::V1::Messages", type: :request do
  let!(:app) { create(:chat_application) }
  let!(:chat) { create(:chat, chat_application: app, number: 1) }
  let(:base_url) { "/api/v1/chat_applications/#{app.token}/chats/1/messages" }
  let(:valid_params) { { message: { body: 'Hello, World!' } } }
  let(:invalid_params) { { message: { body: '' } } }

  describe 'POST /api/v1/chat_applications/:token/chats/:number/messages' do
    it 'creates a new message with sequential number' do
      expect {
        post base_url, params: valid_params
      }.to change(Message, :count).by(1)
    end

    it 'returns the created message with number' do
      post base_url, params: valid_params
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json).to have_key('number')
      expect(json['number']).to eq(1)
    end

    it 'increments message numbers sequentially' do
      post base_url, params: { message: { body: 'Message 1' } }
      post base_url, params: { message: { body: 'Message 2' } }
      post base_url, params: { message: { body: 'Message 3' } }

      messages = chat.messages.order(:created_at)
      expect(messages[0].number).to eq(1)
      expect(messages[1].number).to eq(2)
      expect(messages[2].number).to eq(3)
    end

    it 'returns validation errors for empty body' do
      post base_url, params: invalid_params
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 404 for non-existent application' do
      post "/api/v1/chat_applications/invalid_token/chats/1/messages", params: valid_params
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for non-existent chat' do
      post "/api/v1/chat_applications/#{app.token}/chats/999/messages", params: valid_params
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/chat_applications/:token/chats/:number/messages' do
    let!(:msg1) { create(:message, chat: chat, number: 1, body: 'First') }
    let!(:msg2) { create(:message, chat: chat, number: 2, body: 'Second') }

    it 'returns all messages for the chat' do
      get base_url
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(2)
    end

    it 'returns message numbers and bodies' do
      get base_url
      json = JSON.parse(response.body)
      expect(json[0]['number']).to eq(1)
      expect(json[0]['body']).to eq('First')
      expect(json[1]['number']).to eq(2)
      expect(json[1]['body']).to eq('Second')
    end
  end

  describe 'GET /api/v1/chat_applications/:token/chats/:number/messages/:number' do
    let!(:message) { create(:message, chat: chat, number: 5, body: 'Test Message') }

    it 'returns the specific message' do
      get "#{base_url}/5"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['number']).to eq(5)
      expect(json['body']).to eq('Test Message')
    end

    it 'returns 404 for non-existent message number' do
      get "#{base_url}/999"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/chat_applications/:token/chats/:number/messages/search' do
    let!(:msg1) { create(:message, chat: chat, number: 1, body: 'Hello world') }
    let!(:msg2) { create(:message, chat: chat, number: 2, body: 'Goodbye world') }
    let!(:msg3) { create(:message, chat: chat, number: 3, body: 'Test message') }

    it 'requires a query parameter' do
      get "#{base_url}/search"
      expect(response).to have_http_status(:bad_request)
    end

    it 'returns messages matching the query', skip: 'Requires Elasticsearch' do
      get "#{base_url}/search?q=hello"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to be >= 1
      expect(json.first['body']).to include('hello')
    end
  end
end
