class Api::V1::ChatsController < ApplicationController
  before_action :set_chat_application
  before_action :set_chat, only: [:show, :update]

  # POST /api/v1/chat_applications/:token/chats
  def create
    # Get the next sequential number atomically from Redis
    chat_number = SequentialNumberService.next_chat_number(@chat_application.id)

    # Queue job to persist chat asynchronously (avoid direct MySQL write during request)
    CreateChatJob.perform_later(@chat_application.id, chat_number)

    # Return immediately without waiting for database write
    render json: {
      number: chat_number,
      messages_count: 0
    }, status: :created
  end

  # GET /api/v1/chat_applications/:token/chats
  def index
    @chats = @chat_application.chats.all
    render json: @chats.map { |chat|
      {
        number: chat.number,
        messages_count: chat.messages_count
      }
    }
  end

  # GET /api/v1/chat_applications/:token/chats/:number
  def show
    render json: {
      number: @chat.number,
      messages_count: @chat.messages_count
    }
  end

  # PATCH /api/v1/chat_applications/:token/chats/:number
  def update
    # Currently, no chat attributes can be updated
    render json: { error: 'No attributes to update' }, status: :unprocessable_entity
  end

  private

  def set_chat_application
    @chat_application = ChatApplication.find_by!(token: params[:chat_application_token])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'ChatApplication not found' }, status: :not_found
  end

  def set_chat
    @chat = @chat_application.chats.find_by!(number: params[:number])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Chat not found' }, status: :not_found
  end
end
