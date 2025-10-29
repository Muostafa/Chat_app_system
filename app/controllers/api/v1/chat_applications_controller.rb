class Api::V1::ChatApplicationsController < ApplicationController
  before_action :set_chat_application, only: [:show, :update]

  # POST /api/v1/chat_applications
  def create
    @chat_application = ChatApplication.new(chat_application_params)
    @chat_application.token ||= SecureRandom.hex(16)
    if @chat_application.save
      render json: {
        name: @chat_application.name,
        token: @chat_application.token,
        chats_count: @chat_application.chats_count
      }, status: :created
    else
      render json: { errors: @chat_application.errors }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/chat_applications/:token
  def show
    render json: {
      name: @chat_application.name,
      token: @chat_application.token,
      chats_count: @chat_application.chats_count
    }
  end

  # GET /api/v1/chat_applications
  def index
    @chat_applications = ChatApplication.all
    render json: @chat_applications.map { |app|
      {
        name: app.name,
        token: app.token,
        chats_count: app.chats_count
      }
    }
  end

  # PATCH /api/v1/chat_applications/:token
  def update
    if @chat_application.update(chat_application_params)
      render json: {
        name: @chat_application.name,
        token: @chat_application.token,
        chats_count: @chat_application.chats_count
      }
    else
      render json: { errors: @chat_application.errors }, status: :unprocessable_entity
    end
  end

  private

  def set_chat_application
    @chat_application = ChatApplication.find_by!(token: params[:token])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'ChatApplication not found' }, status: :not_found
  end

  def chat_application_params
    params.require(:chat_application).permit(:name)
  end
end
