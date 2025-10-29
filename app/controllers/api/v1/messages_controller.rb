class Api::V1::MessagesController < ApplicationController
  before_action :set_chat_application
  before_action :set_chat
  before_action :set_message, only: [:show, :update]

  # POST /api/v1/chat_applications/:token/chats/:number/messages
  def create
    # Validate message body
    return render json: { errors: { body: ["can't be blank"] } }, status: :unprocessable_entity if message_params[:body].blank?

    # Get the next sequential number atomically from Redis
    message_number = SequentialNumberService.next_message_number(@chat.id)

    # Queue job to persist message asynchronously (avoid direct MySQL write during request)
    CreateMessageJob.perform_later(@chat.id, message_number, message_params[:body])

    # Return immediately without waiting for database write
    render json: {
      number: message_number
    }, status: :created
  end

  # GET /api/v1/chat_applications/:token/chats/:number/messages
  def index
    @messages = @chat.messages.all
    render json: @messages.map { |message|
      {
        number: message.number,
        body: message.body
      }
    }
  end

  # GET /api/v1/chat_applications/:token/chats/:number/messages/:number
  def show
    render json: {
      number: @message.number,
      body: @message.body
    }
  end

  # PATCH /api/v1/chat_applications/:token/chats/:number/messages/:number
  def update
    # Currently, no message attributes can be updated
    render json: { error: 'No attributes to update' }, status: :unprocessable_entity
  end

  # GET /api/v1/chat_applications/:token/chats/:number/messages/search
  def search
    query = params[:q]
    return render json: { error: 'Query parameter required' }, status: :bad_request if query.blank?

    begin
      # Escape special wildcard characters and convert to lowercase for case-insensitive search
      escaped_query = query.gsub(/([*?])/, '\\\\\1').downcase

      results = Message.search(
        query: {
          bool: {
            must: [
              { wildcard: { "body.keyword": "*#{escaped_query}*" } },
              { term: { chat_id: @chat.id } }
            ]
          }
        }
      )

      render json: results.records.map { |message|
        {
          number: message.number,
          body: message.body
        }
      }
    rescue => e
      render json: { error: 'Search failed' }, status: :internal_server_error
    end
  end

  private

  def set_chat_application
    @chat_application = ChatApplication.find_by!(token: params[:chat_application_token])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'ChatApplication not found' }, status: :not_found
  end

  def set_chat
    @chat = @chat_application.chats.find_by!(number: params[:chat_number])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Chat not found' }, status: :not_found
  end

  def set_message
    @message = @chat.messages.find_by!(number: params[:number])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Message not found' }, status: :not_found
  end

  def message_params
    params.require(:message).permit(:body)
  end
end
